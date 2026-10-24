#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import Foundation
import Testing
import WinSDK

extension OnTheDesktop {
    /// Who is the app in front (§8, `Foreground`), for what the window says of itself isn't always the process that
    /// typed: a classic console's window says it is its client's (cmd.exe) while TSF, and so the DLL, run in the
    /// conhost.exe that draws it; a WebView2's input method client is msedgewebview2.exe, whose window is inside its host
    /// app's. The panel, its notices and the caret reports have to work there too, and still for no other process.
    @Suite(.serialized)
    struct ForegroundTests {
        /// A program started with `commandLine` (no console of the caller's: conhost.exe makes its own window).
        static func start(_ commandLine: String) throws -> PROCESS_INFORMATION {
            var startup = STARTUPINFOW()
            startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
            var info = PROCESS_INFORMATION()
            var line = Array(commandLine.utf16) + [0]
            guard CreateProcessW(nil, &line, nil, nil, false, DWORD(CREATE_NEW_PROCESS_GROUP), nil, nil, &startup, &info) else {
                throw SystemActionError("Couldn't start \(commandLine) (error \(GetLastError()))")
            }
            return info
        }

        static func stop(_ info: PROCESS_INFORMATION) {
            TerminateProcess(info.hProcess, 0)
            WaitForSingleObject(info.hProcess, 5000)
            CloseHandle(info.hThread)
            CloseHandle(info.hProcess)
        }

        /// The processes `parent` started.
        static func children(of parent: DWORD) -> [DWORD] {
            let snapshot = CreateToolhelp32Snapshot(DWORD(TH32CS_SNAPPROCESS), 0)
            guard snapshot != INVALID_HANDLE_VALUE else { return [] }
            defer { CloseHandle(snapshot) }
            var entry = PROCESSENTRY32W()
            entry.dwSize = DWORD(MemoryLayout<PROCESSENTRY32W>.size)
            var found: [DWORD] = []
            var more = Process32FirstW(snapshot, &entry)
            while more {
                if entry.th32ParentProcessID == parent { found.append(entry.th32ProcessID) }
                more = Process32NextW(snapshot, &entry)
            }
            return found
        }

        /// The top-level windows of class `name` that say they are process `pid`'s.
        static func windows(ofClass name: String, reportedBy pid: DWORD) -> [HWND] {
            final class Hunt { var pid: DWORD = 0; var name = ""; var found: [HWND] = [] }
            let hunt = Hunt()
            hunt.pid = pid
            hunt.name = name
            EnumWindows({ window, context in
                let hunt = Unmanaged<Hunt>.fromOpaque(UnsafeRawPointer(bitPattern: Int(context))!).takeUnretainedValue()
                var owner: DWORD = 0
                GetWindowThreadProcessId(window, &owner)
                var name = [WCHAR](repeating: 0, count: 64)
                GetClassNameW(window, &name, 64)
                if owner == hunt.pid, String(decodingCString: name, as: UTF16.self) == hunt.name, let window { hunt.found.append(window) }
                return true
            }, LPARAM(Int(bitPattern: Unmanaged.passUnretained(hunt).toOpaque())))
            return hunt.found
        }

        /// A classic console, as `conhost.exe cmd.exe` opens one (never Windows Terminal): conhost's process, its
        /// client's, and the console's window (which says it is the client's).
        struct Console {
            var host: PROCESS_INFORMATION
            var client: DWORD
            var window: HWND
        }

        static func console() throws -> Console {
            var system = [WCHAR](repeating: 0, count: Int(MAX_PATH))
            let count = Int(GetSystemDirectoryW(&system, UINT(MAX_PATH)))
            let conhost = String(decoding: system.prefix(count), as: UTF16.self) + #"\conhost.exe"#
            let host = try start("\"\(conhost)\" cmd.exe /d /k")
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline {
                for client in children(of: host.dwProcessId) {
                    if let window = windows(ofClass: "ConsoleWindowClass", reportedBy: client).first {
                        return Console(host: host, client: client, window: window)
                    }
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            stop(host)
            throw SystemActionError("conhost.exe opened no console window")
        }

        static func stop(_ console: Console) {
            if let client = OpenProcess(DWORD(PROCESS_TERMINATE), false, console.client) {
                TerminateProcess(client, 0)
                CloseHandle(client)
            }
            stop(console.host)
        }

        /// conhost.exe draws a classic console's window and runs its TSF (the DLL, the client the engine sees), but the
        /// window says it is cmd.exe's: for its conhost it is the app in front and the caret reports in it are the
        /// conhost's to make; for another console's conhost, or any other process, neither.
        @Test(.timeLimit(.minutes(1))) func aClassicConsolesWindowIsItsConhosts() throws {
            let console = try Self.console()
            defer { Self.stop(console) }
            let other = try Self.console()
            defer { Self.stop(other) }
            let host = console.host.dwProcessId
            var reported: DWORD = 0
            GetWindowThreadProcessId(console.window, &reported)
            #expect(reported == console.client && reported != host)

            #expect(Foreground.isInFront(host, foreground: console.window))
            let hwnd = UInt64(UInt(bitPattern: console.window))
            var rect = RECT()
            perMonitorAware { _ = GetWindowRect(console.window, &rect) }  // physical pixels, as `caretBounds` gives them
            let bounds = try #require(Foreground.caretBounds(hwnd: hwnd, pid: host, trusted: true))
            #expect(bounds == CaretRect(x: Int(rect.left), y: Int(rect.top), width: Int(rect.right - rect.left),
                                        height: Int(rect.bottom - rect.top)))
            // Asked again (the answer kept for a second): the same.
            #expect(Foreground.isInFront(host, foreground: console.window))

            // The other console's conhost: not in front, and its reports in this window are ignored; nor this one in the
            // other's window.
            #expect(!Foreground.isInFront(other.host.dwProcessId, foreground: console.window))
            #expect(Foreground.caretBounds(hwnd: hwnd, pid: other.host.dwProcessId, trusted: true) == nil)
            #expect(!Foreground.isInFront(host, foreground: other.window))
            #expect(Foreground.caretBounds(hwnd: UInt64(UInt(bitPattern: other.window)), pid: host, trusted: true) == nil)
            // A process that isn't a conhost.
            #expect(!Foreground.isInFront(GetCurrentProcessId(), foreground: console.window))
            #expect(Foreground.caretBounds(hwnd: hwnd, pid: GetCurrentProcessId(), trusted: true) == nil)
        }

        /// A window of another process inside the app's window (a WebView2's in its host app, a UWP app's in its frame):
        /// that process is in front, as is one whose window has the focus; one whose window is in another app isn't.
        @Test(.timeLimit(.minutes(1))) func aProcessWithAWindowInsideTheAppsIsInFront() throws {
            let python = try StubProvider.python()
            let folder = try temporaryFolder("foreground")
            defer { try? FileManager.default.removeItem(at: folder) }
            // The other process: a child window in the window it is given, its handle printed, then it waits.
            let script = folder.appendingPathComponent("child.py")
            try Data("""
                import ctypes, sys, time
                from ctypes import wintypes as w
                u = ctypes.WinDLL("user32", use_last_error=True)
                u.CreateWindowExW.restype = w.HWND
                u.CreateWindowExW.argtypes = [w.DWORD, w.LPCWSTR, w.LPCWSTR, w.DWORD, ctypes.c_int, ctypes.c_int,
                                              ctypes.c_int, ctypes.c_int, w.HWND, w.HMENU, w.HINSTANCE, w.LPVOID]
                # WS_EX_NOPARENTNOTIFY: nothing sent to the parent's thread, which doesn't pump.
                child = u.CreateWindowExW(0x4, "STATIC", "child", 0x40000000 | 0x10000000, 0, 0, 50, 50,
                                          int(sys.argv[1]), None, None, None)
                print(child or 0, flush=True)
                msg = w.MSG()
                end = time.time() + 60
                while time.time() < end:
                    while u.PeekMessageW(ctypes.byref(msg), None, 0, 0, 1):
                        u.TranslateMessage(ctypes.byref(msg))
                        u.DispatchMessageW(ctypes.byref(msg))
                    time.sleep(0.02)

                """.utf8).write(to: script)
            func popup() throws -> HWND {
                try #require("STATIC".withCString(encodedAs: UTF16.self) {
                    CreateWindowExW(0, $0, nil, DWORD(WS_POPUP), 100, 100, 300, 200, nil, nil, GetModuleHandleW(nil), nil)
                })
            }
            let app = try popup()
            defer { DestroyWindow(app) }
            let another = try popup()
            defer { DestroyWindow(another) }

            let process = Process()
            process.executableURL = python
            process.arguments = ["-I", script.path, String(UInt(bitPattern: app))]
            let output = Pipe()
            process.standardOutput = output
            try process.run()
            defer {
                // Gone before the parent window is destroyed, which would wait on its thread.
                process.terminate()
                process.waitUntilExit()
            }
            var line = Data()
            while !line.contains(UInt8(ascii: "\n")) {
                let byte = output.fileHandleForReading.readData(ofLength: 1)
                if byte.isEmpty { break }
                line += byte
            }
            let printed = UInt(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let child = try #require(HWND(bitPattern: printed), "the other process made no child window")
            #expect(GetParent(child) == app)
            // (The interpreter's, which a launcher on the PATH may have started.)
            var pid: DWORD = 0
            GetWindowThreadProcessId(child, &pid)
            #expect(pid != 0 && pid != GetCurrentProcessId())
            defer {
                if let interpreter = OpenProcess(DWORD(PROCESS_TERMINATE), false, pid) {
                    TerminateProcess(interpreter, 0)
                    CloseHandle(interpreter)
                }
            }

            // Inside the app's window: in front. Not when another window (with nothing of its) is in front.
            #expect(Foreground.isInFront(pid, foreground: app))
            #expect(!Foreground.isInFront(pid, foreground: another))
            // Its window has the focus of the window in front's thread: in front too.
            #expect(Foreground.isInFront(pid, foreground: another, focus: child))
            // The app itself is in front of course; a third process isn't.
            #expect(Foreground.isInFront(GetCurrentProcessId(), foreground: app))
            #expect(!Foreground.isInFront(pid &+ 4, foreground: app))
            // An untrusted client (low integrity, an AppContainer) with a window inside another app's (not
            // ApplicationFrameHost's frame) isn't in front: it could have put it there to show its panel over that app.
            // Its window with the focus still makes it so, and so does its own window in front.
            #expect(!Foreground.isInFront(pid, foreground: app, trusted: false))
            #expect(Foreground.isInFront(pid, foreground: another, focus: child, trusted: false))
            #expect(Foreground.isInFront(GetCurrentProcessId(), foreground: app, trusted: false))
        }
    }
}
#endif
