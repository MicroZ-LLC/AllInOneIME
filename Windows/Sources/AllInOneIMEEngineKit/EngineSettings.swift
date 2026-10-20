import AllInOneIMECore
import Foundation

/// The engine's settings: the core's `config.json` (`Config`, in `%APPDATA%\AllInOneIME` on Windows, or the file
/// `--config` names), read again only when the file changed (by its modification date), as the Mac's `LiveConfig`. A
/// file that doesn't parse reads as the defaults, and says why (`problem`). The Settings app changes it over the pipe
/// (the core's `SettingsService`, wire protocol §12); `allinoneime-cli set-provider` and friends, or a hand edit, too.
public final class EngineSettings: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()
    private var cached: (date: Date?, exists: Bool, config: Config)?
    private var lastProblem: String?

    public init(url: URL = Config.userURL) {
        self.url = url
    }

    /// The settings as of now.
    public var current: Config {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let date = attributes?[.modificationDate] as? Date
        let exists = attributes != nil
        lock.lock()
        defer { lock.unlock() }
        if let cached, cached.date == date, cached.exists == exists { return cached.config }
        let config: Config
        if !exists {
            config = Self.fresh
            lastProblem = nil
        } else {
            do {
                config = try Config.load(from: url)
                lastProblem = nil
            } catch {
                config = Self.fresh
                lastProblem = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
        }
        cached = (date, exists, config)
        return config
    }

    /// Why the file couldn't be read (nil: it could, or there is none).
    public var problem: String? {
        _ = current
        lock.lock()
        defer { lock.unlock() }
        return lastProblem
    }

    /// A new user's settings on Windows: the Mac's for a new user (`Config.fresh`: typing starts in English, the
    /// provider AllInOneIME Cloud), with Chinese added as the second input language, as the Mac adds it once its pack
    /// is installed: the Windows installer ships the pack's data (rime-data), so Shift switches English and 中文 from the
    /// start.
    public static var fresh: Config {
        var config = Config.fresh
        if !config.inputLanguages.contains(.chinese) { config.inputLanguages.append(.chinese) }
        config.normalizeLanguages()
        return config
    }

    /// The interface language's code ("zh-Hans", "en", "fr"): the config's `uiLanguage`, else the system's, among the
    /// languages the String Catalog has (`EngineLanguage`; Simplified Chinese and English without it).
    public func interfaceLanguage(_ config: Config) -> String {
        let shipped = UIText.shipped
        return InterfaceLanguage.code(forSetting: config.uiLanguage, shipped: shipped)
            ?? InterfaceLanguage.pick(preferred: Self.preferredLanguages, shipped: shipped)
    }

    /// The user's languages, in their order: the core's (`Platform.userLanguages`), on Windows Windows' own list
    /// (`GetUserPreferredUILanguages`: "zh-CN", "en-US"), which Foundation's `Locale.preferredLanguages` doesn't read
    /// there (it says "en-001" whatever the user has). The command line reads the same.
    public static var preferredLanguages: [String] { Platform.current.userLanguages.preferred }
}
