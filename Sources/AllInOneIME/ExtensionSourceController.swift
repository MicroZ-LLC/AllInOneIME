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

/// Main thread.
@MainActor
final class ExtensionSourceController: ObservableObject {
    static let shared = ExtensionSourceController()

    /// What is known of each source's clone, by address (sources.json).
    @Published private(set) var statuses: [String: ExtensionSourceStatus] = [:]
    /// The sources git is at work on now (Check Now, Update, …), by address.
    @Published private(set) var busy: Set<String> = []

    /// Where the clones are, and the git that's run (the self-test passes its own folder and git).
    var root = ExtensionSources.directory
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

    /// At launch: the statuses, a check of the sources that check by themselves about 30 s later, then once a day.
    func start() {
        reload()
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
        guard !busy.contains(source.url), let status = statuses[source.url] else { return nil }
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

    func reclone(_ source: ExtensionSource) async {
        await perform(source) { try await $0.reclone(source, $1) }
    }

    /// Checks out `pin` (nil: back to following the branch, then checked).
    func pin(_ source: ExtensionSource, to pin: String?) async {
        if let pin {
            await perform(source) { try await $0.pin(source, to: pin, $1) }
        } else {
            var following = source
            following.pin = nil
            await check(following)
        }
    }

    /// Clones a source to review it (not trusted, nothing loaded). Its status is kept only once it's enabled.
    func cloneForReview(_ source: ExtensionSource) async throws -> ExtensionSourceManager.Clone {
        busy.insert(source.url)
        defer { busy.remove(source.url) }
        return try await manager().clone(source)
    }

    /// Enable, after the review: trusted from now on, with this address.
    func trust(_ clone: ExtensionSourceManager.Clone) {
        var status = clone.status
        status.trusted = true
        setStatus(status, for: status.url)
    }

    /// Cancel in the review: the clone is deleted.
    func discard(_ source: ExtensionSource) {
        plainManager.discard(source)
    }

    /// Remove: the clone to the Trash, its status dropped (the config is the caller's).
    func remove(_ source: ExtensionSource) throws {
        try plainManager.trash(source)
        reload()
        setStatus(nil, for: source.url)
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
        tr("有 \(count) 个更新", count == 1 ? "1 update" : "\(count) updates")
    }

    /// "a1b2c3d · 2 hr ago".
    static func commit(_ sha: String?, _ date: Date?, now: Date = Date()) -> String {
        [sha.map { String($0.prefix(7)) }, date.map { DashboardText.ago($0, now: now, chinese: UIText.chinese) }]
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
            return tr("仓库的历史变了（强制推送），不能直接更新：请重新克隆。", "The repository's history changed (a force push), so it can't simply update: re-clone it.")
        }
    }
}
