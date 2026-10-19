#if os(Windows)
import Foundation
@testable import AllInOneIMECore

/// Where the tests find on Windows the programs they find in /bin and /usr/bin on the Mac.
enum WindowsTestTools {
    /// Windows' System32 folder ("C:\Windows\System32").
    static var systemFolder: String { WindowsPrograms.systemProgram("") }

    /// A program in System32, as Windows writes its path ("C:\Windows\System32\where.exe").
    static func systemProgram(_ name: String) -> String { WindowsPrograms.systemProgram(name) }

    /// Git for Windows' Unix tools (its usr\bin: sh, echo, rev, sleep, yes), as a PATH; nil without Git.
    static var gitTools: String? {
        WindowsPrograms.gitRoot(nil).map { WindowsPrograms.windowsPath($0.appendingPathComponent("usr/bin", isDirectory: true)) }
    }
}
#endif
