import Foundation
@testable import AllInOneIMECore

/// What this platform has, for the tests of what only some have (`.enabled(if:)`).
enum Available {
    /// A JavaScript engine (`Platform.scripts`): JavaScriptCore on Apple platforms, QuickJS-ng on Windows, Linux and
    /// Android.
    static let javaScript = Platform.current.scripts.makeContext() != nil
    /// The system's date detection (`Platform.dates`: NSDataDetector), which reads 明天 and "tomorrow" too.
    static let systemDates = !(Platform.current.dates is RulesOnlyDateDetector)
    /// The system's date detection reading Chinese: NSDataDetector reads 明天 or 周五 only for a user with Chinese among
    /// their languages (System Settings › Language & Region), as a Chinese typist's Mac has; a Mac in English alone (a
    /// GitHub runner's) finds no date in 明天. Asked of NSDataDetector itself, not of the core.
    static let chineseSystemDates: Bool = {
        #if canImport(Darwin)
        let text = "明天"
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        return systemDates && detector?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.date != nil
        #else
        return false
        #endif
    }()
    /// Messages.app, the program `@imessage` needs: a Mac's.
    static let messagesApp = FileManager.default.fileExists(atPath: "/System/Applications/Messages.app")
    /// Whether a file's or a folder's permissions keep this process out: not as root, who reads, lists and searches
    /// whatever their mode says (a container's user: swift's image and GitHub's job containers run as root).
    static let permissionsApply: Bool = {
        #if os(Windows)
        return true
        #else
        return geteuid() != 0
        #endif
    }()
    /// The language packs' archives (.tar.xz), made and unpacked by the system's tar as bsdtar is asked to
    /// (`LanguagePackLibrary.unpack`): the Mac's and Windows'. Linux has no packs yet (no Rime there): its tar is GNU
    /// tar, which has no --no-mac-metadata or --no-fflags, and a minimal one (swift's image) has no xz.
    static let packArchives: Bool = {
        #if os(Linux)
        return false
        #else
        return true
        #endif
    }()
}
