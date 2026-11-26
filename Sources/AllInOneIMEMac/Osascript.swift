import AllInOneIMECore
import Foundation

/// osascript as the input method runs it (`@agent`'s Terminal window, `@imessage`'s Messages): through `ProcessOutput`,
/// so that a long answer never fills its pipe and an app that never answers the Apple event can't hold the caller up.
public enum Osascript {
    public static let executable = URL(fileURLWithPath: "/usr/bin/osascript")

    /// How long a script may take: enough for the app to start cold and for the user to answer macOS's first prompt to
    /// let AllInOneIME control it (AppleScript itself would wait two minutes for each event). ALLINONEIME_OSASCRIPT_TIMEOUT,
    /// a number of seconds above 0, says otherwise (the tests').
    public static let timeout: TimeInterval = ProcessInfo.processInfo.environment["ALLINONEIME_OSASCRIPT_TIMEOUT"]
        .flatMap(TimeInterval.init).flatMap { $0 > 0 ? $0 : nil } ?? 30

    /// Runs osascript with `arguments`, `input` on its standard input (the script, for "-"); blocks the calling thread
    /// (never the main one) until it ended, `timeout` at most (then `ProcessOutput.TimedOut`).
    public static func run(_ arguments: [String], input: Data? = nil) throws -> ProcessOutput.Result {
        try ProcessOutput.run(executable, arguments, input: input, timeout: timeout)
    }
}
