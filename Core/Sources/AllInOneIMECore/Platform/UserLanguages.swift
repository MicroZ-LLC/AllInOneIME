import Foundation

/// The user's languages, in their order: what a new user's translation language comes from (`Config.fresh`), and the
/// interface language when the settings name none. Foundation's `Locale.preferredLanguages` on Apple platforms and
/// Linux; on Windows, Windows' own list (`WindowsUserLanguages`: `GetUserPreferredUILanguages`), which Foundation
/// doesn't read there (it says "en-001" whatever the user has).
public protocol UserLanguages: Sendable {
    /// Language tags, the user's first first ("zh-Hans-CN", "en-US"; Windows writes "zh-CN"). Never empty: "en" when
    /// there is none.
    var preferred: [String] { get }
}

/// Foundation's list (`Locale.preferredLanguages`): System Settings → General → Language & Region on the Mac.
public struct FoundationUserLanguages: UserLanguages {
    public init() {}

    public var preferred: [String] {
        let languages = Locale.preferredLanguages
        return languages.isEmpty ? ["en"] : languages
    }
}

extension Platform {
    /// Windows' own list on Windows, Foundation's elsewhere.
    public static var systemUserLanguages: any UserLanguages {
        #if os(Windows)
        return WindowsUserLanguages()
        #else
        return FoundationUserLanguages()
        #endif
    }
}
