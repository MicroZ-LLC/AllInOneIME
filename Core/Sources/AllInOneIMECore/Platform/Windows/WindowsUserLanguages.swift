#if os(Windows)
import Foundation
import WinSDK

/// The user's languages as Windows has them (Settings → Time & language → Language & region, the Windows display
/// language first): `GetUserPreferredUILanguages`, by name ("zh-CN", "en-US"). Foundation's `Locale.preferredLanguages`
/// doesn't read them on Windows. Foundation's list when Windows gives none.
public struct WindowsUserLanguages: UserLanguages {
    public init() {}

    public var preferred: [String] {
        let languages = Self.windowsList
        return languages.isEmpty ? FoundationUserLanguages().preferred : languages
    }

    /// `GetUserPreferredUILanguages`' list: empty if it fails.
    static var windowsList: [String] {
        var count: ULONG = 0
        var size: ULONG = 0
        let flags = DWORD(MUI_LANGUAGE_NAME)
        guard GetUserPreferredUILanguages(flags, &count, nil, &size), size > 0 else { return [] }
        var buffer = [WCHAR](repeating: 0, count: Int(size))
        guard GetUserPreferredUILanguages(flags, &count, &buffer, &size) else { return [] }
        // NUL-separated, ending with two.
        return buffer.split(separator: 0).map { String(decoding: $0, as: UTF16.self) }.filter { !$0.isEmpty }
    }
}
#endif
