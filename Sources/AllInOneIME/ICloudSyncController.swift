import AllInOneIMECore
import AllInOneIMERime
import AppKit
import CoreGraphics

/// Sync through iCloud in the running input method (`ICloudSyncEngine`, `ICloudSync`): it runs when the input method
/// starts, about 5 s after the config (or the jargon list, the recent questions) changes on this Mac, when iCloud changes
/// the shared folder (watched, and looked at every 5 minutes besides), and on Sync Now. The learned words are Rime's
/// user-dictionary sync (`RimeService.syncUserData`): when the input method starts, every 30 minutes, and on Sync Now; as
/// it drops the sessions for a moment, the timed ones wait until no key has been pressed for half a minute and nothing is
/// being composed.
///
/// Runs go on a serial queue of their own, never the main thread (a folder event or a poll never holds up typing); only
/// writing the config file hops to the main thread, as Settings writes it there. What comes in is written the way
/// `@config` writes it, so the input method and Settings read it again (`allInOneIMEConfigChanged`); what needs more than
/// reading (the menu bar icon, fuzzy pinyin, the interface language, a language pack) is applied here. The published state
/// is the main thread's.
@MainActor
final class ICloudSyncController: ObservableObject {
    static let shared = ICloudSyncController()

    enum Status: Equatable {
        case off
        /// iCloud Drive isn't there.
        case unavailable
        case syncing
        case synced(Date)
        case waiting
        case failed(String)
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var lastSync: Date?
    /// iCloud Drive is there and can be written (as of the last look).
    @Published private(set) var driveAvailable = true
    /// The AllInOneIME folder is in iCloud Drive ("Remove from iCloud…" is offered).
    @Published private(set) var folderExists = false
    /// Values from iCloud not applied here, by key.
    @Published private(set) var refused: [String: ICloudSync.Problem] = [:]
    /// A run is going on (on the sync queue).
    @Published private(set) var running = false

    /// What the runs use: iCloud Drive and the user's files; the self-test gives temporary ones.
    var engine = ICloudSyncEngine(folder: .iCloudDrive(), environment: liveEnvironment)
    /// Rime's sync with `sync_dir` set to `folder` (the self-test's Rime runs in a folder of its own); false when Rime
    /// couldn't start it now.
    var syncRime: @MainActor (URL) -> Bool = { folder in
        guard let user = RimeService.shared.userDataDir, RimeService.shared.isReady else { return false }
        do {
            try RimeSync.setSyncDir(folder, userDataDir: user)
        } catch {
            log.error("iCloud sync: could not set Rime's sync folder: \(String(describing: error), privacy: .public)")
            return false
        }
        return RimeService.shared.syncUserData()
    }
    /// Rime's `sync_dir` taken out again (sync or learned words turned off), only when it is `folder`, the one set here.
    var stopRime: @MainActor (URL) -> Void = { folder in
        guard let user = RimeService.shared.userDataDir else { return }
        _ = try? RimeSync.removeSyncDir(ifItIs: folder, userDataDir: user)
    }
    /// This Mac's record was copied from another Mac (Migration Assistant): Rime makes a new installation id too.
    var resetRimeInstallation: @MainActor () -> Void = {
        guard let user = RimeService.shared.userDataDir else { return }
        if (try? RimeSync.resetInstallationID(userDataDir: user)) == true {
            log.notice("iCloud sync: copied from another Mac; Rime gets an installation id of its own")
        }
    }
    /// Seconds since a key was last pressed anywhere (the timed Rime syncs wait for a pause in typing).
    var secondsSinceKey: () -> TimeInterval = { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) }
    /// Something is being composed in a text field (the timed Rime syncs wait for it to end).
    var composing: @MainActor () -> Bool = { AllInOneIMEInputController.activeController?.composer.isComposing ?? false }
    /// The things a run changed that need more than reading the config again (the self-test records them).
    var applyChanges: @MainActor (ICloudSyncEngine.Report) -> Void = { ICloudSyncController.applyLive($0) }

    private let queue = DispatchQueue(label: "AllInOneIME.iCloudSync", qos: .utility)
    private var started = false
    private var pending: DispatchWorkItem?
    /// Another run was asked for while one was going on.
    private var again = false
    private var watchers: [DispatchSourceFileSystemObject] = []
    /// What is watched: each folder with its file number (a folder deleted and made again is watched anew).
    private var watched: [String] = []
    private var poll: Timer?
    private var rimeTimer: Timer?
    private var lastRimeSync: Date?
    private var rimeWanted = false
    /// Whether Rime's `sync_dir` may be ours (nil: not known yet, at start): taken out once sync or the learned words go off.
    private var rimeSyncDirSet: Bool?
    /// Shown, not live: the settings images (`show`).
    private var sample = false

    static let debounce: TimeInterval = 5
    static let pollInterval: TimeInterval = 5 * 60
    static let rimeInterval: TimeInterval = 30 * 60
    static let rimeIdle: TimeInterval = 30

    /// The checks' view of this Mac: which providers have a key (the keychain item's attributes, never the key), the
    /// AWS profiles, the providers offered.
    nonisolated static var liveEnvironment: ICloudSync.Environment {
        ICloudSync.Environment(hasKey: { APIKeys.source($0) != .none }, awsProfiles: { AWSSharedConfig.profileNames() },
                               offeredProviders: Provider.offered)
    }

    /// The setting as the config file has it now.
    private var settings: ICloudSyncSettings { ((try? Config.load(from: engine.configURL)) ?? .default).iCloudSync }

    /// Rime's sync folder in the shared one.
    private var rimeFolder: URL { engine.folder.url.appendingPathComponent(ICloudSync.rimeFolder) }

    /// When the input method starts: watches, timers and a first run a moment later (Rime's once it's ready).
    func start() {
        guard !started, !sample else { return }
        started = true
        rewatch()
        poll = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { _ in
            MainActor.assumeIsolated { ICloudSyncController.shared.runIfOn() }
        }
        rimeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { ICloudSyncController.shared.rimeIfDue() }
        }
        rimeWanted = true
        schedule(after: 3)
    }

    /// A file it watches changed (or Settings saved): a run in about 5 s, later changes pushing it back.
    func changed() { schedule(after: Self.debounce) }

    /// Sync Now (and the switches in Settings): at once, the learned words too.
    func syncNow() {
        run()
        if settings.enabled, settings.learnedWords { syncLearnedWords() }
    }

    private func schedule(after delay: TimeInterval) {
        pending?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { ICloudSyncController.shared.run() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func runIfOn() {
        if settings.enabled { run() }
    }

    /// One run on the sync queue (one more after it when asked for meanwhile), and what it changed applied.
    func run() {
        pending?.cancel()
        pending = nil
        guard !sample else { return }
        guard !running else {
            again = true
            return
        }
        running = true
        var engine = self.engine
        // The config file is written on the main thread, as Settings and @config write it.
        engine.writeConfig = { config, old, keys, url in
            try DispatchQueue.main.sync { try AIConfig.writing(config, from: old, keys: keys, at: url) }
        }
        queue.async {
            let on = ((try? Config.load(from: engine.configURL)) ?? .default).iCloudSync
            let available = engine.folder.isAvailable
            let report = engine.run()
            let state = ICloudSync.State.load(from: engine.stateURL)
            let exists = engine.folder.exists
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    ICloudSyncController.shared.finish(report, state: state, settings: on, available: available, exists: exists)
                }
            }
        }
    }

    private func finish(_ report: ICloudSyncEngine.Report, state: ICloudSync.State, settings on: ICloudSyncSettings,
                        available: Bool, exists: Bool) {
        running = false
        driveAvailable = available
        folderExists = exists
        lastSync = state.lastSync
        refused = report.refused
        switch report.outcome {
        case .off: status = .off
        case .unavailable: status = .unavailable
        case .synced: status = .synced(state.lastSync ?? Date())
        case .waiting: status = .waiting
        case let .failed(message):
            status = .failed(message)
            log.error("iCloud sync failed: \(message, privacy: .public)")
        }
        if !(on.enabled && on.learnedWords), rimeSyncDirSet != false {
            stopRime(rimeFolder)
            rimeSyncDirSet = false
        }
        if report.newMachine { resetRimeInstallation() }
        for (key, problem) in report.rejected.sorted(by: { $0.key < $1.key }) {
            log.notice("iCloud sync: \(key, privacy: .public) from iCloud not applied: \(problem.rawValue, privacy: .public)")
        }
        if !report.replacedCommands.isEmpty {
            log.notice("iCloud sync: custom commands merged; iCloud's of the same name kept over this Mac's: \(report.replacedCommands.joined(separator: ", "), privacy: .public)")
        }
        // A join changing what is hidden from the AI is said in the log.
        if report.joining.contains(.settings), report.configKeys.contains("redaction") {
            log.notice("iCloud sync: joining took the switches for hiding sensitive information from iCloud")
        }
        if report.joining.contains(.hiddenWords), report.configKeys.contains("redaction") {
            log.notice("iCloud sync: joining merged the hidden words with iCloud's")
        }
        if let aside = report.setAside {
            log.error("iCloud sync: a file in iCloud couldn't be read; set aside as \(aside, privacy: .public)")
        }
        if let aside = report.questionsSetAside {
            log.error("iCloud sync: the recent questions on this Mac couldn't be read; set aside as \(aside, privacy: .public)")
        }
        if !report.applied.isEmpty || !report.uploaded.isEmpty {
            log.notice("iCloud sync: \(report.applied.count) in, \(report.uploaded.count) out")
        }
        if !report.configKeys.isEmpty || report.jargonChanged || report.questionsChanged { applyChanges(report) }
        rewatch()
        // Turned on just now: the learned words too, without waiting for the timer.
        if on.enabled, on.learnedWords, lastRimeSync == nil { rimeWanted = true }
        if again {
            again = false
            run()
        }
    }

    /// The learned words: Rime's sync into the shared folder's `rime/`, the other Macs' snapshots downloaded first.
    func syncLearnedWords() {
        guard !sample, settings.enabled, settings.learnedWords, engine.folder.isAvailable else { return }
        let folder = engine.folder
        try? FileManager.default.createDirectory(at: rimeFolder, withIntermediateDirectories: true)
        folder.downloadAll(in: ICloudSync.rimeFolder)
        rimeSyncDirSet = true
        if syncRime(rimeFolder) {
            lastRimeSync = Date()
            rimeWanted = false
            log.notice("iCloud sync: learned words synced with Rime")
        }
    }

    /// Every minute: the learned words when they're due (at start, then every 30 minutes), nothing typed for a while and
    /// nothing being composed.
    private func rimeIfDue() {
        guard settings.enabled, settings.learnedWords else { return }
        let due = rimeWanted || lastRimeSync.map { Date().timeIntervalSince($0) >= Self.rimeInterval } ?? true
        guard due, secondsSinceKey() >= Self.rimeIdle, !composing() else { return }
        syncLearnedWords()
    }

    /// "Remove from iCloud…" (confirmed in Settings, which turns sync off first): the folder to the Trash, Rime's sync
    /// folder taken out, and this Mac's record forgotten (turned on again, it joins as a new Mac). `done` gets nil, or the
    /// error.
    func removeFromICloud(done: @escaping @MainActor (String?) -> Void) {
        stopRime(rimeFolder)
        rimeSyncDirSet = false
        let engine = self.engine
        queue.async {
            var failure: String?
            do {
                try engine.folder.remove()
                engine.forget()
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            let exists = engine.folder.exists
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let sync = ICloudSyncController.shared
                    sync.folderExists = exists
                    if failure == nil {
                        sync.lastSync = nil
                        sync.lastRimeSync = nil
                        sync.status = .off
                    }
                    done(failure)
                }
            }
        }
    }

    /// "Remove from iCloud…" for the hidden words or the recent questions (Settings turns its switch off first): only
    /// those taken out of iCloud; this Mac keeps its own.
    func removeFromICloud(_ category: ICloudSync.Category, done: @escaping @MainActor (String?) -> Void) {
        let engine = self.engine
        queue.async {
            var failure: String?
            do {
                try engine.removeFromICloud(category)
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { done(failure) } }
        }
    }

    /// "Clear" of the recent questions in Settings: every Mac drops the questions asked before now.
    func questionsCleared() {
        let engine = self.engine, now = Date()
        queue.async { engine.recordQuestionsClear(at: now) }
        changed()
    }

    /// The recent questions deleted because "Remember recent questions" was turned off: no Clear for the other Macs.
    func questionsForgotten() {
        let engine = self.engine
        queue.async { engine.forgetQuestionsSeen() }
    }

    /// Turning it on in Settings: only with iCloud Drive there.
    func canTurnOn() -> Bool {
        driveAvailable = engine.folder.isAvailable
        return driveAvailable
    }

    /// For `@doctor`.
    var facts: Doctor.Facts.ICloudSyncFacts {
        var facts = Doctor.Facts.ICloudSyncFacts()
        let on = settings
        facts.enabled = on.enabled
        guard on.enabled else { return facts }
        facts.available = engine.folder.isAvailable
        let state = ICloudSync.State.load(from: engine.stateURL)
        facts.lastSync = state.lastSync
        if case let .failed(message) = status { facts.lastError = message }
        facts.waiting = status == .waiting
        facts.refused = state.rejected.mapValues(\.problem)
        facts.checked = Date()
        return facts
    }

    /// The settings images: a status of its own, nothing read or synced.
    func show(status: Status, lastSync: Date?, folderExists: Bool = true) {
        sample = true
        self.status = status
        self.lastSync = lastSync
        self.folderExists = folderExists
        driveAvailable = true
    }

    // MARK: Watching

    /// The folders whose changes start a run: the config's, the jargon list's and the recent questions' on this Mac, and
    /// the shared one while sync is on (iCloud Drive itself while that isn't there yet, to see it come). A folder deleted
    /// and made again (another file number) is watched anew.
    private func rewatch() {
        let config = (try? Config.load(from: engine.configURL)) ?? .default
        var folders = [engine.configURL.deletingLastPathComponent().path]
        if config.iCloudSync.enabled {
            folders.append(config.jargonURL.deletingLastPathComponent().path)
            folders.append(engine.questionsURL.deletingLastPathComponent().path)
            folders.append(engine.folder.exists ? engine.folder.url.path : engine.folder.url.deletingLastPathComponent().path)
        }
        let keys = Array(Set(folders)).sorted().map { path -> String in
            var info = stat()
            return stat(path, &info) == 0 ? "\(path)#\(info.st_ino)" : path
        }
        guard keys != watched else { return }
        watchers.forEach { $0.cancel() }
        watchers = keys.compactMap { key in
            let path = String(key.split(separator: "#").first ?? Substring(key))
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { ICloudSyncController.shared.changed() } }
            source.setCancelHandler { close(fd) }
            source.resume()
            return source
        }
        watched = keys
    }

    // MARK: Applying

    /// What reading the config again doesn't do by itself: Settings and the input method told, the menu bar icon,
    /// fuzzy pinyin (Rime deployed again), the interface language, a language pack for an input language added.
    static func applyLive(_ report: ICloudSyncEngine.Report) {
        let config = LiveConfig.current
        NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
        if report.configKeys.contains("menuBarIcon") { MenuBarIcon.shared.apply(config.menuBarIcon) }
        if report.configKeys.contains("fuzzyPinyin") { RimeFuzzy.apply(config.fuzzyPinyin) }
        if report.configKeys.contains("uiLanguage") {
            UIText.choice = config.uiLanguage
            SettingsWindow.shared.updateTitle()
        }
        if report.configKeys.contains("inputLanguages") {
            let packs = LanguagePackManager.shared
            for language in config.inputLanguages where !packs.isUsable(language) {
                if let pack = LanguagePack.for(language) { packs.download(pack) }
            }
        }
    }
}
