#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import Foundation
import Testing
import WinSDK

extension OnTheDesktop.ConsoleHoldTests {
    /// The session ending while the program still runs (logoff, shutdown): the console's process, which loads user32,
    /// is told so through its hidden window (`WM_ENDSESSION`, as Windows sends it then), never through its control
    /// handler, and deletes the prompt's file before Windows ends it.
    @Test(.timeLimit(.minutes(1))) func theSessionEndingDeletesThePrompt() throws {
        try #require(FileManager.default.fileExists(atPath: debugEngine.path), "build the engine first (swift build)")
        let folder = try temporaryFolder("hold-logoff")
        defer { try? FileManager.default.removeItem(at: folder) }
        let prompts = folder.appendingPathComponent("prompts", isDirectory: true)
        try Data("@echo waiting %*\r\n@ping -n 30 127.0.0.1 >nul\r\n".utf8).write(to: folder.appendingPathComponent("wait.cmd"))
        let probe = try ConsoleProbe(folder: folder)
        let path = folder.withUnsafeFileSystemRepresentation { String(cString: $0!) }
        let pid = try testShellThread.syncThrowing {
            try testWindowsSystem().startInConsole(["wait", "--"], prompt: "line one\nline two", path: path, promptFolder: prompts)
        }
        let process = try #require(OpenProcess(DWORD(SYNCHRONIZE) | DWORD(PROCESS_TERMINATE), false, pid))
        defer {
            TerminateProcess(process, 0)
            CloseHandle(process)
        }
        let deadline = Date().addingTimeInterval(20)
        while !probe.screen(pid).contains("waiting"), Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: prompts.path)) ?? []).count == 1)
        var window: HWND?
        while window == nil, Date() < deadline {
            window = Self.window(of: pid, className: ConsoleHold.EndSession.className)
            if window == nil { Thread.sleep(forTimeInterval: 0.05) }
        }
        let found = try #require(window, "the console's process has no window for the session's end")
        var answer: DWORD_PTR = 0
        // What Windows sends a process's top-level windows as the user logs off (ENDSESSION_LOGOFF).
        #expect(SendMessageTimeoutW(found, UINT(WM_QUERYENDSESSION), 0, LPARAM(bitPattern: 0x8000_0000), UINT(SMTO_ABORTIFHUNG), 5000,
                                    &answer) != 0 && answer == 1)
        #expect(SendMessageTimeoutW(found, UINT(WM_ENDSESSION), 1, LPARAM(bitPattern: 0x8000_0000), UINT(SMTO_ABORTIFHUNG), 5000,
                                    &answer) != 0)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: prompts.path)) ?? []).isEmpty)
    }

    /// Process `pid`'s top-level window of class `className`.
    static func window(of pid: DWORD, className: String) -> HWND? {
        className.withCString(encodedAs: UTF16.self) { name in
            var after: HWND?
            while let next = FindWindowExW(nil, after, name, nil) {
                var owner: DWORD = 0
                GetWindowThreadProcessId(next, &owner)
                if owner == pid { return next }
                after = next
            }
            return nil
        }
    }
}
#endif
