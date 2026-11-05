import Foundation
@testable import AllInOneIMECore

/// What this platform has, for the tests of what only some have (`.enabled(if:)`).
enum Available {
    /// A JavaScript engine (`Platform.scripts`): JavaScriptCore on Apple platforms, QuickJS-ng on Windows, Linux and
    /// Android.
    static let javaScript = Platform.current.scripts.makeContext() != nil
    /// The system's date detection (`Platform.dates`: NSDataDetector), which reads 明天 and "tomorrow" too.
    static let systemDates = !(Platform.current.dates is RulesOnlyDateDetector)
    /// Messages.app, the program `@imessage` needs: a Mac's.
    static let messagesApp = FileManager.default.fileExists(atPath: "/System/Applications/Messages.app")
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
