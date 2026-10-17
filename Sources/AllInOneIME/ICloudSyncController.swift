import AllInOneIMECore
import AllInOneIMERime
import AppKit
import CoreGraphics

/// Sync through iCloud in the running input method (`ICloudSyncEngine`, `ICloudSync`): it runs when the input method
/// starts, about 5 s after the config (or the jargon list, the recent questions) changes on this Mac, when iCloud changes
/// the shared folder (watched, and looked at every 5 minutes besides), and on Sync Now. The learned words are Rime's own
/// sync (`RimeService.syncUserData`): when the input method starts, every 30 minutes, and on Sync Now; as it drops the
/// sessions for a moment, the timed ones wait until no key has been pressed for half a minute.
///
/// What comes in is written into the config file the way `@config` writes it, so the input method and Settings read it
/// again (`allInOneIMEConfigChanged`); what needs more than reading (the menu bar icon, fuzzy pinyin, the interface
/// language, a language pack) is applied here. Main thread only.
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
    /// Rime's `sync_dir` taken out again (sync or learned words turned off).
    var stopRime: @MainActor () -> Void = {
        guard let user = RimeService.shared.userDataDir else { return }
        _ = try? RimeSync.setSyncDir(nil, userDataDir: user)
    }
    /// Seconds since a key was last pressed anywhere (the timed Rime syncs wait for a pause in typing).
    var secondsSinceKey: () -> TimeInterval = { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) }
    /// The things a run changed that need more than reading the config again (the self-test records them).
    var applyChanges: @MainActor (ICloudSyncEngine.Report) -> Void = { ICloudSyncController.applyLive($0) }

    private var started = false
    private var pending: DispatchWorkItem?
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var watched: [String] = []
    private var poll: Timer?
    private var rimeTimer: Timer?
    private var lastRimeSync: Date?
    private var rimeWanted = false
    /// Whether Rime's `sync_dir` may be set (nil: not known yet, at start): taken out once sync or the learned words go off.
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

    /// One run, and what it changed applied.
    func run() {
        pending?.cancel()
        pending = nil
        guard !sample else { return }
        let on = settings
        driveAvailable = engine.folder.isAvailable
        let report = engine.run()
        folderExists = engine.folder.exists
        let state = ICloudSync.State.load(from: engine.stateURL)
        lastSync = state.lastSync
        refused = report.refused
        switch report.outcome {
        case .off: status = .off
        case .unavailable: status = .unavailable
        case .synced: status = .synced(state.lastSync ?? engine.now())
        case .waiting: status = .waiting
        case let .failed(message):
            status = .failed(message)
            log.error("iCloud sync failed: \(message, privacy: .public)")
        }
        if !(on.enabled && on.learnedWords), rimeSyncDirSet != false {
            stopRime()
            rimeSyncDirSet = false
        }
        for (key, problem) in report.rejected.sorted(by: { $0.key < $1.key }) {
            log.notice("iCloud sync: \(key, privacy: .public) from iCloud not applied: \(problem.rawValue, privacy: .public)")
        }
        if !report.replacedCommands.isEmpty {
            log.notice("iCloud sync: custom commands merged; iCloud's of the same name kept over this Mac's: \(report.replacedCommands.joined(separator: ", "), privacy: .public)")
        }
        if let aside = report.setAside {
            log.error("iCloud sync: settings.json couldn't be read; set aside as \(aside, privacy: .public)")
        }
        if !report.applied.isEmpty || !report.uploaded.isEmpty {
            log.notice("iCloud sync: \(report.applied.count) in, \(report.uploaded.count) out")
        }
        if !report.configKeys.isEmpty || report.jargonChanged || report.questionsChanged { applyChanges(report) }
        rewatch()
        // Turned on just now: the learned words too, without waiting for the timer.
        if on.enabled, on.learnedWords, lastRimeSync == nil { rimeWanted = true }
    }

    /// The learned words: Rime's sync into the shared folder's `rime/`, the other Macs' snapshots downloaded first.
    func syncLearnedWords() {
        guard !sample, settings.enabled, settings.learnedWords, engine.folder.isAvailable else { return }
        let folder = engine.folder
        try? FileManager.default.createDirectory(at: folder.url.appendingPathComponent(ICloudSync.rimeFolder), withIntermediateDirectories: true)
        folder.downloadAll(in: ICloudSync.rimeFolder)
        rimeSyncDirSet = true
        if syncRime(folder.url.appendingPathComponent(ICloudSync.rimeFolder)) {
            lastRimeSync = Date()
            rimeWanted = false
            log.notice("iCloud sync: learned words synced with Rime")
        }
    }

    /// Every minute: the learned words when they're due (at start, then every 30 minutes) and nothing was typed for a while.
    private func rimeIfDue() {
        guard settings.enabled, settings.learnedWords else { return }
        let due = rimeWanted || lastRimeSync.map { Date().timeIntervalSince($0) >= Self.rimeInterval } ?? true
        guard due, secondsSinceKey() >= Self.rimeIdle else { return }
        syncLearnedWords()
    }

    /// "Remove from iCloud…" (confirmed in Settings, which turns sync off first): the folder to the Trash, Rime's sync
    /// folder taken out, and this Mac's record forgotten (turned on again, it joins as a new Mac). Nil, or the error.
    func removeFromICloud() -> String? {
        stopRime()
        rimeSyncDirSet = false
        do {
            try engine.folder.remove()
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        engine.forget()
        folderExists = engine.folder.exists
        lastSync = nil
        lastRimeSync = nil
        status = .off
        return nil
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
    /// the shared one (while sync is on).
    private func rewatch() {
        let config = (try? Config.load(from: engine.configURL)) ?? .default
        var folders = [engine.configURL.deletingLastPathComponent().path]
        if config.iCloudSync.enabled {
            folders.append(config.jargonURL.deletingLastPathComponent().path)
            folders.append(engine.questionsURL.deletingLastPathComponent().path)
            if engine.folder.exists { folders.append(engine.folder.url.path) }
        }
        folders = Array(Set(folders)).sorted()
        guard folders != watched else { return }
        watchers.forEach { $0.cancel() }
        watchers = folders.compactMap { path in
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { ICloudSyncController.shared.folderChanged() } }
            source.setCancelHandler { close(fd) }
            source.resume()
            return source
        }
        watched = folders
    }

    private func folderChanged() {
        // Only while it is on, or to notice it was turned on (the config's folder).
        changed()
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
