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
}
