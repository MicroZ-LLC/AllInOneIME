#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import Foundation
import Testing
import WinSDK

extension OnTheDesktop {
    /// The engine's real `WindowsSystem` (the other tests record what the host asks of it instead): opening through the
    /// shell.
    @Suite(.serialized)
    struct WindowsSystemTests {
        static func path(_ url: URL) -> String { url.withUnsafeFileSystemRepresentation { String(cString: $0!) } }

        /// `@open` of a file: the shell starts what opens it (a batch file runs), and that process, and only it, gets
        /// the foreground (`AllowSetForegroundWindow(pid)`, never `ASFW_ANY`).
        @Test(.timeLimit(.minutes(1))) func openStartsWhatOpensTheFile() throws {
            let folder = try temporaryFolder("open")
            defer { try? FileManager.default.removeItem(at: folder) }
            let marker = folder.appendingPathComponent("opened.txt")
            let script = folder.appendingPathComponent("opened.cmd")
            try Data("@echo opened> \"\(Self.path(marker))\"\r\n".utf8).write(to: script)
            let pid = try WindowsSystem.shellOpen(Self.path(script))
            #expect(pid != nil && pid != 0)
            let deadline = Date().addingTimeInterval(20)
            while !FileManager.default.fileExists(atPath: marker.path), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            #expect(FileManager.default.fileExists(atPath: marker.path))
            #expect(throws: SystemActionError.self) { try WindowsSystem().open(Self.path(folder.appendingPathComponent("missing.txt"))) }
        }
    }
}
#endif
