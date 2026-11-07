import AllInOneIMECore
import Foundation

// A new version, told in a macOS notification (0.7.0). The daily check (`UpdateSchedule`) only ever said so on the
// About page and in the menu bar panel, where most users never look. Now, when a check in the background finds a newer
// version this Mac can install, one notification says so, once a version: Update installs it as the About page's
// button does, Don't Show Again turns these notifications off (`Config.notifiesUpdates`; About turns them on again),
// and clicking it opens Settings → About. Never a dialog or a window: a key being typed never lands on a button of it.
// macOS is asked for permission only as the first one is about to be posted; not allowed, nothing else happens (the
// About page's line and the menu bar panel's are still there). The input method posts them through macOS's notification
// center; the tests through a fake (`UpdateNoticePoster`), so no test ever posts a real one.

/// One of the updater's notifications: a newer version (with Update and Don't Show Again), or an update started from one
/// that didn't go in.
public struct UpdateNotice: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case available
        case failed
    }

    public var kind: Kind
    public var version: String
    public var title: String
    public var body: String

    public init(kind: Kind, version: String, title: String, body: String) {
        self.kind = kind
        self.version = version
        self.title = title
        self.body = body
    }

    /// "AllInOneIME 0.7.1 is available", and what's new in the interface language if the manifest says it in that
    /// language (`summary`), else a line asking to update.
    public static func available(_ manifest: UpdateManifest) -> UpdateNotice {
        UpdateNotice(kind: .available, version: manifest.version,
                     title: tr("AllInOneIME \(manifest.version) 可以更新了", "AllInOneIME \(manifest.version) is available"),
                     body: summary(of: manifest, language: UIText.language)
                         ?? tr("现在更新，获得最新的修正。", "Update now to get the latest fixes."))
    }

    /// An update started from a notification didn't go in: the About page says why.
    public static func failed(_ version: String) -> UpdateNotice {
        UpdateNotice(kind: .failed, version: version, title: tr("没能更新到 \(version)", "Couldn't update to \(version)"),
                     body: tr("点这里在 设置 →「关于」里看原因。", "Click to see why in Settings → About."))
    }

    /// The release's summary in `language` (an interface language's code: "en", "zh-Hans", "ja"), by that code or its
    /// language's ("zh" for "zh-Hans" and "zh-Hant", as the About page shows it); nil when the manifest has none in it
    /// (it has English and Chinese: `make update-manifest`).
    public static func summary(of manifest: UpdateManifest, language: String) -> String? {
        for code in [language, InterfaceLanguage.Tag(language).language] {
            if let text = manifest.summary?[code]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        }
        return nil
    }
}

/// Whether macOS lets the input method show notifications.
public enum UpdateNoticePermission: Sendable {
    /// Not asked yet: asked as the first notification is about to be posted.
    case notAsked
    case allowed
    /// Not allowed (the user said no, or turned them off in System Settings): nothing is posted.
    case denied
}

/// What the user did with a notification.
public enum UpdateNoticeAction: String, Sendable {
    /// Clicked it: Settings → About.
    case open
    /// Its Update button: the About page's install.
    case update
    /// Its Don't Show Again button: `Config.notifiesUpdates` off.
    case dontShowAgain
}

/// Where the updater's notifications go: macOS's notification center in the input method, a fake in the tests.
@MainActor
public protocol UpdateNoticePoster: AnyObject {
    /// What the user allowed, without asking.
    func permission() async -> UpdateNoticePermission
    /// Asks the user (macOS's prompt): whether they allowed it.
    func askPermission() async -> Bool
    func post(_ notice: UpdateNotice) async
}

/// When a newer version gets its notification, and what its buttons do. The versions told and the one an Update from a
/// notification is installing are this Mac's (`defaults`: the input method's, with the updater's other state; never
/// synced); the switches are the config's (`checkForUpdates`, `notifiesUpdates`). Main thread.
@MainActor
public final class UpdateNotifier {
    /// The last version told: a notification for it, or a check the user asked for that showed it.
    public static let notifiedKey = "updateLastNotified"
    /// The version an Update clicked in a notification is installing, until how it went is known (by the input method
    /// that starts after the helper, when the helper did the rest).
    public static let installingKey = "updateInstallingFromNotice"

    public var poster: any UpdateNoticePoster
    public var defaults: UserDefaults
    /// The settings now; nil while the config file doesn't parse (nothing is posted then: what the user chose isn't known).
    public var config: () -> Config?
    /// Don't Show Again: `notifiesUpdates` off in the config file (only that key: `Config.change`).
    public var turnOff: () throws -> Void
    /// Update: the About page's install (download, verify, stage, the helper's swap, the restart). The version it is
    /// installing; nil when none was started.
    public var install: () -> String?
    /// The notification clicked: Settings → About.
    public var openAbout: () -> Void
    /// A notification on its way (macOS may be asking the user): another check's finding waits for the next check.
    private var posting = false

    /// With the config file at `configURL` (read for the switches, written by Don't Show Again); nothing installs and
    /// nothing opens until `install` and `openAbout` are given.
    public init(poster: any UpdateNoticePoster, defaults: UserDefaults = .standard, configURL: URL = Config.defaultURL) {
        self.poster = poster
        self.defaults = defaults
        config = { try? Config.load(from: configURL) }
        turnOff = { try Config.change(at: configURL) { $0.notifiesUpdates = false } }
        install = { nil }
        openAbout = {}
    }

    /// The last version told.
    public var lastNotified: String? { defaults.string(forKey: Self.notifiedKey) }

    /// Whether `version` is newer than the last version told.
    private func isNew(_ version: String) -> Bool {
        lastNotified.map { SemVer.compare(version, $0) > 0 } ?? true
    }

    /// Both switches on, and `version` newer than the last version told.
    private func wants(_ version: String) -> Bool {
        guard let config = config(), config.checkForUpdates, config.notifiesUpdates else { return false }
        return isNew(version)
    }

    /// A check in the background found `manifest`: its notification, when it is an update this Mac can install
    /// (`availability`; `installable`: the installed copy, which the About page updates in place), newer than the last
    /// version told, and both switches are on. macOS is asked for permission now if it never was; not allowed, nothing
    /// is posted. Whether it was posted.
    @discardableResult
    public func found(_ manifest: UpdateManifest, availability: UpdateAvailability, installable: Bool) async -> Bool {
        guard availability == .available, installable, !posting, wants(manifest.version) else { return false }
        posting = true
        defer { posting = false }
        let allowed: Bool
        switch await poster.permission() {
        case .allowed: allowed = true
        case .denied: allowed = false
        case .notAsked: allowed = await poster.askPermission()
        }
        // Turned off while macOS asked, say.
        guard allowed, wants(manifest.version) else { return false }
        await poster.post(.available(manifest))
        defaults.set(manifest.version, forKey: Self.notifiedKey)
        return true
    }

    /// A check the user asked for found `manifest`: the About page shows it, so it counts as told (no notification for
    /// it later).
    public func shown(_ manifest: UpdateManifest, availability: UpdateAvailability) {
        guard availability == .available, isNew(manifest.version) else { return }
        defaults.set(manifest.version, forKey: Self.notifiedKey)
    }

    /// What the user did with a notification. Throws when Don't Show Again can't write the config file.
    public func respond(_ action: UpdateNoticeAction) throws {
        switch action {
        case .open: openAbout()
        case .update:
            if let version = install() { defaults.set(version, forKey: Self.installingKey) }
        case .dontShowAgain: try turnOff()
        }
    }

    /// An update to `version` failed before the restart (downloading, checking or staging it, or starting the helper):
    /// a short notification if a notification's Update started it (the About page says what went wrong).
    public func installFailed(_ version: String) async {
        guard defaults.string(forKey: Self.installingKey) == version else { return }
        defaults.removeObject(forKey: Self.installingKey)
        await postFailure(version)
    }

    /// At launch, what the last update did (`UpdateResult`; nil: none since): when a notification's Update started it and
    /// it didn't go in, a short notification says so (the About page says why).
    public func restarted(after result: UpdateResult?) async {
        guard let installing = defaults.string(forKey: Self.installingKey), let result else { return }
        defaults.removeObject(forKey: Self.installingKey)
        if !result.ok, result.to == installing { await postFailure(installing) }
    }

    /// Only where notifications are allowed: macOS isn't asked for this one.
    private func postFailure(_ version: String) async {
        guard await poster.permission() == .allowed else { return }
        await poster.post(.failed(version))
    }
}
