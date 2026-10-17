import AllInOneIMECore
import AppKit

// Extension sources in the input method (`ExtensionSources` in the core has the rules): what Settings shows of each
// source's clone, the git work it starts (in the background, never while a key is handled), and the daily check.
//
// - A check only fetches and notes what's new (`ExtensionSourceStatus.updates`): Settings → Custom Commands shows
//   "N updates" on the source and a badge on the page; nothing pops up, nothing changes by itself.
// - The status of each clone is in sources.json next to the clones: the command line (`--add-source`,
//   `--update-sources`) writes it too, and Settings reads it again when its window becomes key.
// - The sources themselves, and their bundles' folders in the load list, are in the config: Settings changes them through
//   its model (Enable, Remove, the pin), the command line in the file; the input method follows the file
//   (`LiveConfig`, `LiveExtensions`).
// - Only reviewed code loads: a folder of the sources folder in the load list that isn't a trusted source's bundle (a
//   config copied from another Mac, a lost sources.json) is left out by `LiveExtensions` (`ExtensionSourceGate`) and taken
//   out of the config at launch and when Settings shows the page. Clones for a review wait in staging until Enable.

/// Main thread.
@MainActor
final class ExtensionSourceController: ObservableObject {
    static let shared = ExtensionSourceController()

    /// What is known of each source's clone, by address (sources.json).
    @Published private(set) var statuses: [String: ExtensionSourceStatus] = [:]
    /// The sources git is at work on now (Check Now, Update, …), by address.
    @Published private(set) var busy: Set<String> = []

    /// Where the clones are, and the git that's run (the self-test passes its own folder and git).
    var root = ExtensionSources.directory {
        didSet { ExtensionSourceGate.root = root }
    }
    var git: (any GitRunning)?
    /// Where a removed source's clone goes: the Trash (the self-test deletes its own instead).
    var trashItem: @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    /// The sources to check by themselves (the config's, as it is now).
    var loadSources: () -> [ExtensionSource] = { LiveConfig.current.extensionSources }
    private var timer: Timer?

    private init() {}

    /// The core's manager with the user's git (its environment read once, off the main thread).
    func manager() async -> ExtensionSourceManager {
        if git == nil {
            git = await Task.detached { await ProcessGitRunner.user() }.value
        }
        return ExtensionSourceManager(root: root, git: git!, trashItem: trashItem)
    }

    /// The manager for what needs no git (deleting, trashing a clone).
    private var plainManager: ExtensionSourceManager {
        ExtensionSourceManager(root: root, git: git ?? ProcessGitRunner(environment: [:]), trashItem: trashItem)
    }

    var statusFile: URL { root.appendingPathComponent(ExtensionSources.statusFileName) }

    /// sources.json again (the command line may have changed it).
    func reload() {
        let read = ExtensionSourceStatus.load(from: statusFile)
        if read != statuses { statuses = read }
    }

    /// The statuses as the file has them now (`reload`) are the ones changed: what the command line wrote meanwhile stays.
    /// Sets (or drops) a source's status and keeps it.
    func setStatus(_ status: ExtensionSourceStatus?, for url: String) {
        statuses[url] = status
        do {
            try ExtensionSourceStatus.save(statuses, to: statusFile)
        } catch {
            log.error("extension sources: couldn't save their status: \(String(describing: error), privacy: .public)")
        }
    }

    /// How many new commits the trusted, unpinned sources have waiting: the page's badge.
    func updateCount(for sources: [ExtensionSource]) -> Int {
        sources.filter { $0.pin == nil }.reduce(0) { count, source in
            guard let status = statuses[source.url], ExtensionSources.isTrusted(source, status) else { return count }
            return count + status.updates.count
        }
    }

    // MARK: Schedule

    /// Posted by `--add-source` and `--update-sources` (another process) once they've written: Settings reads the config and
    /// the statuses again.
    nonisolated static let changedNotification = Notification.Name("com.aipinyin.inputmethod.AIPinyin.extensionSourcesChanged")

    nonisolated static func postChanged() {
        DistributedNotificationCenter.default().postNotificationName(changedNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// Statuses to show without keeping them (the settings' images: sample sources, never the user's).
    func show(_ shown: [String: ExtensionSourceStatus]) {
        statuses = shown
    }

    /// At launch: leftovers of an interrupted add or re-clone removed, unreviewed folders out of the load list, the
    /// statuses, a check of the sources that check by themselves about 30 s later, then once a day.
    func start() {
        plainManager.removeLeftovers()
        reload()
        quarantineConfigFile()
        DistributedNotificationCenter.default().addObserver(forName: Self.changedNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                ExtensionSourceController.shared.reload()
                NotificationCenter.default.post(name: .allInOneIMEConfigChanged, object: nil)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ExtensionSources.firstCheckDelay) { [weak self] in
            self?.checkAll(automatic: true)
        }
        timer = Timer.scheduledTimer(withTimeInterval: ExtensionSources.checkInterval, repeats: true) { _ in
            MainActor.assumeIsolated { ExtensionSourceController.shared.checkAll(automatic: true) }
        }
    }

    /// Checks each source that's due (`ExtensionSources.shouldCheck`), one after another; one failing doesn't stop the
    /// others. `automatic`: only those with autoCheck.
    func checkAll(automatic: Bool) {
        let due = loadSources().filter { ExtensionSources.shouldCheck($0, status: statuses[$0.url], automatic: automatic) }
        guard !due.isEmpty else { return }
        Task {
            for source in due { await check(source) }
        }
    }

    // MARK: Git work

    /// Runs `work` for `source` (one thing at a time per source), keeping the status it returns; a failure is kept as
    /// the source's error (git's own words), and returned.
    @discardableResult
    func perform(_ source: ExtensionSource,
                 _ work: @escaping @Sendable (ExtensionSourceManager, ExtensionSourceStatus) async throws -> ExtensionSourceStatus) async -> Error? {
        guard !busy.contains(source.url) else { return SourceBusy() }
        guard let status = statuses[source.url] else { return ExtensionSourceError.notTrusted }
        busy.insert(source.url)
        defer { busy.remove(source.url) }
        let manager = await manager()
        do {
            let updated = try await work(manager, status)
            reload()  // the command line may have written meanwhile: only this source's status is replaced
            setStatus(updated, for: source.url)
            return nil
        } catch {
            reload()
            var failed = statuses[source.url] ?? status
            failed.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if case ExtensionSourceError.notFastForward = error { failed.fastForward = false }
            setStatus(failed, for: source.url)
            log.error("extension source \(ExtensionSources.folderName(for: source.url), privacy: .public): \(failed.error ?? "", privacy: .public)")
            return error
        }
    }

    func check(_ source: ExtensionSource) async {
        let before = statuses[source.url]?.updates.count ?? 0
        await perform(source) { try await $0.check(source, $1) }
        let after = statuses[source.url]?.updates.count ?? 0
        if after > before {
            log.notice("extension source \(ExtensionSources.folderName(for: source.url), privacy: .public): \(after) updates")
        }
    }

    func update(_ source: ExtensionSource) async {
        await perform(source) { try await $0.update(source, $1) }
    }

    /// Checks out `pin`, or with nil goes back to the branch's newest commit (a fast-forward, as Update). Returns the
    /// error, if any: the caller saves the new pin in the config only when there's none.
    func pin(_ source: ExtensionSource, to pin: String?) async -> Error? {
        if let pin {
            return await perform(source) { try await $0.pin(source, to: pin, $1) }
        }
        let following = ExtensionSource(url: source.url, path: source.path, branch: source.branch, pin: nil,
                                        autoCheck: source.autoCheck, authHint: source.authHint)
        return await perform(following) { try await $0.update(following, $1) }
    }

    /// Clones a source into staging for the review (not trusted, not in place, nothing loaded).
    func stageForReview(_ source: ExtensionSource) async throws -> ExtensionSourceManager.Clone {
        busy.insert(source.url)
        defer { busy.remove(source.url) }
        return try await manager().stage(source)
    }

    /// Enable, after the review: the staged clone in place, trusted from now on with this address (the statuses read
    /// again first: the command line may have written meanwhile).
    func install(_ staged: ExtensionSourceManager.Clone) throws {
        let installed = try plainManager.install(staged)
        reload()
        var status = installed.status
        status.trusted = true
        setStatus(status, for: status.url)
    }

    /// Cancel in the review: the staged clone is deleted (never the one in place).
    func discard(_ staged: ExtensionSourceManager.Clone) {
        plainManager.discard(staged)
    }

    /// Remove: the clone to the Trash, its status dropped (the config is the caller's). The status goes even when the
    /// Trash refuses; that error is returned for the caller to say.
    func remove(_ source: ExtensionSource) -> Error? {
        var failure: Error?
        do {
            try plainManager.trash(source)
        } catch {
            failure = error
            log.error("extension source: couldn't move the clone to the Trash: \(String(describing: error), privacy: .public)")
        }
        reload()
        setStatus(nil, for: source.url)
        return failure
    }

    // MARK: Only reviewed code

    /// The config file without the unreviewed folders of the sources folder in its load list (written only if it had any).
    func quarantineConfigFile(_ url: URL = Config.defaultURL) {
        guard var config = try? Config.load(from: url) else { return }
        let removed = ExtensionSources.quarantine(&config, statuses: statuses, root: root)
        guard !removed.isEmpty else { return }
        try? config.write(to: url)
        log.notice("extension sources: \(removed.count) unreviewed folder(s) taken out of the load list")
    }
}

/// Another git job for this source is under way (Pin, Update, a check): nothing was done.
struct SourceBusy: LocalizedError {
    var errorDescription: String? { tr("这个来源正在处理别的事，稍后再试。", "This source is busy with something else; try again in a moment.") }
}

/// What `LiveExtensions` loads (`ExtensionSources.loadFolders`): the config's folders less those of the sources folder
/// that aren't a trusted source's bundle, a source's folder read only as its one bundle. sources.json is read again only
/// when it changed (one stat a call), and the folders worked out again only when something they come from changed.
/// Main thread only, as `LiveExtensions`.
enum ExtensionSourceGate {
    nonisolated(unsafe) private static var cachedStatuses: (url: URL, date: Date?, statuses: [String: ExtensionSourceStatus])?
    nonisolated(unsafe) private static var cachedFolders: (key: [String], folders: [ExtensionStore.Folder])?
    /// The sources folder (`ExtensionSourceController.root`, which sets it).
    nonisolated(unsafe) static var root = ExtensionSources.directory

    static func folders(_ config: Config, found: [String]) -> [ExtensionStore.Folder] {
        let statuses = statuses(root)
        let key = [root.path, String(describing: cachedStatuses?.date), String(config.findRaycastScripts)]
            + config.extensionFolders + ["|"] + config.hiddenExtensionFolders + ["|"] + found
            + config.extensionSources.map { $0.url + "\u{0}" + ($0.path ?? "") }
        if let cachedFolders, cachedFolders.key == key { return cachedFolders.folders }
        let folders = ExtensionSources.loadFolders(config, found: found, statuses: statuses, root: root)
        cachedFolders = (key, folders)
        return folders
    }

    private static func statuses(_ root: URL) -> [String: ExtensionSourceStatus] {
        let file = root.appendingPathComponent(ExtensionSources.statusFileName)
        let date = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        if let cachedStatuses, cachedStatuses.url == file, cachedStatuses.date == date { return cachedStatuses.statuses }
        let statuses = ExtensionSourceStatus.load(from: file)
        cachedStatuses = (file, date, statuses)
        return statuses
    }
}

// MARK: - Text

enum ExtensionSourceText {
    /// The prominent warning of the review.
    static func unsigned(_ url: String) -> String {
        tr("这个来源没有签名：会运行来自 \(url) 的程序", "This source isn't signed: it will run programs from \(url).")
    }

    /// Always under a git error, then the source's own hint, if it has one.
    static func gitHint(_ url: String) -> String {
        tr("这里用的是你自己的 git 和 SSH 设置；先在终端里确认 git ls-remote \(url) 能用。",
           "This uses your own git and SSH setup; check that git ls-remote \(url) works in Terminal.")
    }

    static func updates(_ count: Int) -> String {
        count == 1 ? tr("有 1 个更新", "1 update") : tr("有 \(count) 个更新", "\(count) updates")
    }

    /// "a1b2c3d · 2 hr ago".
    static func commit(_ sha: String?, _ date: Date?, now: Date = Date()) -> String {
        [sha.map { String($0.prefix(7)) }, date.map { DashboardText.ago($0, now: now, language: UIText.language) }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    static func describe(_ error: Error) -> String {
        guard let error = error as? ExtensionSourceError else { return error.localizedDescription }
        switch error {
        case let .invalidURL(url):
            return tr("不是 Git 地址（ssh://、git@主机:、https:// 或 file://）：\(url)", "Not a Git address (ssh://, git@host:, https:// or file://): \(url)")
        case .notHTTPS: return tr("不用明文的 http://：请用 https:// 或 ssh。", "Plain http:// isn't used: use https:// or ssh.")
        case .gitNotInstalled:
            return tr("git 需要命令行开发工具：在终端里运行 xcode-select --install。", "git needs the Command Line Tools: run xcode-select --install in Terminal.")
        case let .git(message): return message
        case let .timedOut(seconds): return tr("git 在 \(Int(seconds)) 秒内没有完成。", "git didn't finish within \(Int(seconds)) seconds.")
        case let .noBundle(path):
            return path.map { tr("\($0) 里没有 extension.json。", "\($0) has no extension.json.") }
                ?? tr("这个仓库里没有 extension.json。", "The repository has no extension.json.")
        case .severalBundles: return tr("有好几个扩展包，选一个。", "There are several bundles: pick one.")
        case .alreadyAdded: return tr("这个来源已经加过了。", "This source is already added.")
        case .notAdded: return tr("没有这个来源。", "No such source is added.")
        case .notTrusted: return tr("还没有检查并启用。", "Not reviewed and enabled yet.")
        case .notFastForward:
            return tr("仓库的历史变了（强制推送），不能直接更新：重新克隆，并重新检查一遍。",
                      "The repository's history changed (a force push), so it can't simply update: re-clone it and review it again.")
        case let .invalidRef(ref): return tr("不是有效的分支、标签或提交名：\(ref)", "Not a valid branch, tag or commit name: \(ref)")
        case .credentialsInURL:
            return tr("地址里不要写用户名、密码或令牌：交给 git 的凭据助手保存（git help credential）。",
                      "Don't put a user name, password or token in the address: let git's credential helper keep them (git help credential).")
        case let .outsideClone(path): return tr("\(path) 指向仓库外面。", "\(path) leads out of the repository.")
        }
    }
}
