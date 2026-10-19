#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import Foundation
import Testing
import WinSDK

extension OnTheDesktop {
    /// The engine's real `WindowsSystem` (the other tests record what the host asks of it instead): the clipboard and
    /// opening through the shell.
    @Suite(.serialized)
    struct WindowsSystemTests {
        static func path(_ url: URL) -> String { url.withUnsafeFileSystemRepresentation { String(cString: $0!) } }

        /// Ctrl+C and Ctrl+V's clipboard, for real: what is copied is on the clipboard, owned by the clipboard thread's
        /// message-only window (with none, `SetClipboardData` fails), and reads back as it was, from any thread. The
        /// clipboard as it was before (the user's, in a desktop session) is put back after, and what the test copies is
        /// kept out of the clipboard's history.
        @Test(.timeLimit(.minutes(1))) func theClipboardRoundTrips() throws {
            var system = testWindowsSystem()
            system.excludedFromHistory = true
            let saved = ClipboardContents.take(on: testClipboardThread)
            defer { saved.restore(on: testClipboardThread) }
            let texts = ["AllInOneIME clipboard test \(UUID().uuidString)",
                         "你好，“引号”和‘单引号’ 👋\r\nline two\ttab \\ \" ' & % ^",
                         String(repeating: "长文本 long text. ", count: 5_000)]
            for text in texts {
                #expect(system.copy(text))
                let owner = GetClipboardOwner()
                #expect(owner != nil && owner == testClipboardThread.window)
                #expect(system.readClipboard() == text)
                // On the clipboard thread itself too, as the engine reads it (Ctrl+V).
                #expect(testClipboardThread.sync { system.readClipboard() } == text)
            }
        }

        /// The clipboard's thread is never the shell's: with the shell's busy (ShellExecuteExW on a share that is
        /// offline, on a DDE conversation), the engine still copies and reads, and another program's Ctrl+C, whose
        /// `EmptyClipboard` waits for the owner's window to answer `WM_DESTROYCLIPBOARD`, isn't held up.
        @Test(.timeLimit(.minutes(1))) func theClipboardAnswersWhileTheShellIsBusy() throws {
            var system = testWindowsSystem()
            system.excludedFromHistory = true
            let saved = ClipboardContents.take(on: testClipboardThread)
            defer { saved.restore(on: testClipboardThread) }
            let busy = DispatchSemaphore(value: 0), started = DispatchSemaphore(value: 0)
            testShellThread.async {
                started.signal()
                busy.wait()
            }
            defer { busy.signal() }
            started.wait()
            /// `work` on a thread of its own, if it is done within 5 s.
            func within5s<T>(_ work: @escaping @Sendable () -> T) -> T? {
                let done = DispatchSemaphore(value: 0)
                nonisolated(unsafe) var result: T?
                Thread.detachNewThread {
                    result = work()
                    done.signal()
                }
                return done.wait(timeout: .now() + 5) == .success ? result : nil
            }
            let text = "AllInOneIME clipboard test \(UUID().uuidString)"
            let copier = system
            #expect(within5s { copier.copy(text) } == true)
            #expect(GetClipboardOwner() == testClipboardThread.window)
            #expect(within5s { copier.readClipboard() } == text)
            // Another program empties it, as its Ctrl+C does: the owner is told, and answers.
            let emptied = within5s { () -> Bool in
                guard OpenClipboard(nil) else { return false }
                defer { CloseClipboard() }
                return EmptyClipboard()
            }
            #expect(emptied == true)
        }

        /// The rights to take the foreground `shellOpen` gives, in order.
        final class Allowed: @unchecked Sendable {
            private let lock = NSLock()
            private var pids: [DWORD] = []
            func add(_ pid: DWORD) { lock.lock(); pids.append(pid); lock.unlock() }
            var all: [DWORD] { lock.lock(); defer { lock.unlock() }; return pids }
        }

        /// `ASFW_ANY`, (DWORD)-1: any process may take the foreground.
        static let anyProcess = DWORD.max

        /// `@open` of a file: the shell starts what opens it (a batch file runs), and that process, and only it, gets
        /// the right to take the foreground (`AllowSetForegroundWindow(pid)`, never `ASFW_ANY`).
        @Test(.timeLimit(.minutes(1))) func openStartsWhatOpensTheFile() throws {
            let folder = try temporaryFolder("open")
            defer { try? FileManager.default.removeItem(at: folder) }
            let marker = folder.appendingPathComponent("opened.txt")
            let script = folder.appendingPathComponent("opened.cmd")
            try Data("@echo opened> \"\(Self.path(marker))\"\r\n".utf8).write(to: script)
            let allowed = Allowed()
            let opened = try testShellThread.syncThrowing {
                try WindowsSystem.shellOpen(Self.path(script), allowForeground: { allowed.add($0) })
            }
            let started = try #require(opened.started)
            #expect(started != 0)
            // The process the shell started has it, last; no process had ASFW_ANY.
            #expect(allowed.all == opened.allowed)
            #expect(allowed.all.last == started)
            #expect(!allowed.all.contains(Self.anyProcess) && !allowed.all.contains(0))
            let deadline = Date().addingTimeInterval(20)
            while !FileManager.default.fileExists(atPath: marker.path), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            #expect(FileManager.default.fileExists(atPath: marker.path))
            let missing = Self.path(folder.appendingPathComponent("missing.txt"))
            #expect(throws: SystemActionError.self) { try testWindowsSystem().open(missing) }
        }

        /// What a program already running would show (an address in the browser, a folder in Explorer: the shell hands
        /// it over and starts nothing, `hProcess` is NULL) gets the right to take the foreground first, before the shell
        /// asks it; what the shell starts, after.
        @Test(.timeLimit(.minutes(1))) func aProgramAlreadyRunningGetsTheForegroundFirst() throws {
            let folder = try temporaryFolder("open-running")
            defer { try? FileManager.default.removeItem(at: folder) }
            let script = folder.appendingPathComponent("opened.cmd")
            try Data("@exit /b 0\r\n".utf8).write(to: script)
            let running: DWORD = GetCurrentProcessId()
            let allowed = Allowed()
            let opened = try testShellThread.syncThrowing {
                try WindowsSystem.shellOpen(Self.path(script), handler: { _ in running }, allowForeground: { allowed.add($0) })
            }
            let started = try #require(opened.started)
            #expect(allowed.all == [running, started])
            // None running: only what the shell started.
            let alone = Allowed()
            let second = try testShellThread.syncThrowing {
                try WindowsSystem.shellOpen(Self.path(script), handler: { _ in nil }, allowForeground: { alone.add($0) })
            }
            #expect(alone.all == [try #require(second.started)])
        }

        /// The program already running that would open something: Explorer for a folder, the browser for an address, a
        /// file type's program; found running by its image, in this session, by a window it shows.
        @Test(.timeLimit(.minutes(1))) func theProgramAlreadyRunningIsFoundByWhatOpensIt() throws {
            var windows = [WCHAR](repeating: 0, count: Int(MAX_PATH))
            let count = Int(GetWindowsDirectoryW(&windows, UINT(MAX_PATH)))
            let explorer = String(decoding: windows.prefix(count), as: UTF16.self) + #"\explorer.exe"#
            let folder = try temporaryFolder("open-handler")
            defer { try? FileManager.default.removeItem(at: folder) }
            #expect(WindowsSystem.handlerExecutable(for: Self.path(folder))?.lowercased() == explorer.lowercased())
            #expect(WindowsSystem.handlerExecutable(for: Self.path(folder.appendingPathComponent("notes.txt")))?.lowercased().hasSuffix(".exe") == true)
            if let browser = WindowsSystem.handlerExecutable(for: "https://example.com/") {
                #expect(browser.lowercased().hasSuffix(".exe"))
            }
            #expect(WindowsSystem.handlerExecutable(for: Self.path(folder.appendingPathComponent("no-type"))) == nil)

            // A program with a window on the screen (Python's): found by its image, written in any case.
            let script = folder.appendingPathComponent("window.py")
            try Data("""
                import ctypes, time
                from ctypes import wintypes as w
                u = ctypes.WinDLL("user32")
                u.CreateWindowExW.restype = w.HWND
                u.CreateWindowExW.argtypes = [w.DWORD, w.LPCWSTR, w.LPCWSTR, w.DWORD, ctypes.c_int, ctypes.c_int,
                                              ctypes.c_int, ctypes.c_int, w.HWND, w.HMENU, w.HINSTANCE, w.LPVOID]
                window = u.CreateWindowExW(0, "STATIC", "AllInOneIME test", 0x00CF0000 | 0x10000000, 50, 50, 200, 100,
                                           None, None, None, None)
                print(window or 0, flush=True)
                msg = w.MSG()
                end = time.time() + 60
                while time.time() < end:
                    while u.PeekMessageW(ctypes.byref(msg), None, 0, 0, 1):
                        u.DispatchMessageW(ctypes.byref(msg))
                    time.sleep(0.02)

                """.utf8).write(to: script)
            let process = Process()
            process.executableURL = try StubProvider.python()
            process.arguments = ["-I", script.path]
            let output = Pipe()
            process.standardOutput = output
            try process.run()
            defer {
                process.terminate()
                process.waitUntilExit()
            }
            var line = Data()
            while !line.contains(UInt8(ascii: "\n")) {
                let byte = output.fileHandleForReading.readData(ofLength: 1)
                if byte.isEmpty { break }
                line += byte
            }
            let window = try #require(HWND(bitPattern: UInt(String(decoding: line, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0), "Python made no window")
            var pid: DWORD = 0
            GetWindowThreadProcessId(window, &pid)
            defer {
                if let interpreter = OpenProcess(DWORD(PROCESS_TERMINATE), false, pid) {
                    TerminateProcess(interpreter, 0)
                    CloseHandle(interpreter)
                }
            }
            let handle = try #require(OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid))
            var path = [WCHAR](repeating: 0, count: 1024)
            var size = DWORD(path.count)
            #expect(QueryFullProcessImageNameW(handle, 0, &path, &size))
            CloseHandle(handle)
            let image = String(decoding: path.prefix(Int(size)), as: UTF16.self)
            #expect(WindowsSystem.windowProcess(image: image.uppercased()) == pid)
            #expect(WindowsSystem.windowProcess(image: Self.path(folder.appendingPathComponent("nothing.exe"))) == nil)
        }
    }
}

/// What is on the clipboard, every format held in global memory (text, HTML, files, a bitmap as its DIB), to put back
/// after a test that changes it.
struct ClipboardContents {
    var formats: [(format: UINT, data: Data)] = []

    /// Formats whose data is a GDI object or the owner's own, not global memory: not copied (a bitmap comes back from
    /// its DIB, which Windows makes of it).
    static func isGlobalMemory(_ format: UINT) -> Bool {
        let gdi: Set<UINT> = [UINT(CF_BITMAP), UINT(CF_METAFILEPICT), UINT(CF_PALETTE), UINT(CF_ENHMETAFILE),
                              UINT(CF_OWNERDISPLAY), UINT(CF_DSPBITMAP), UINT(CF_DSPMETAFILEPICT), UINT(CF_DSPENHMETAFILE)]
        return !gdi.contains(format) && !(UINT(CF_PRIVATEFIRST)...UINT(CF_GDIOBJLAST)).contains(format)
    }

    static func take(on thread: SystemThread) -> ClipboardContents {
        thread.sync {
            var contents = ClipboardContents()
            guard let window = thread.window, WindowsSystem.openClipboard(window) else { return contents }
            defer { CloseClipboard() }
            var format: UINT = 0
            while true {
                format = EnumClipboardFormats(format)
                guard format != 0 else { break }
                guard isGlobalMemory(format), let memory = GetClipboardData(format), let pointer = GlobalLock(memory) else { continue }
                contents.formats.append((format, Data(bytes: pointer, count: Int(GlobalSize(memory)))))
                GlobalUnlock(memory)
            }
            return contents
        }
    }

    /// Back on the clipboard, kept out of its history (it is there already).
    func restore(on thread: SystemThread) {
        thread.sync {
            guard let window = thread.window, WindowsSystem.openClipboard(window) else { return }
            defer { CloseClipboard() }
            EmptyClipboard()
            for (format, data) in formats { _ = WindowsSystem.set(format, data) }
            if !formats.isEmpty { WindowsSystem.excludeFromHistory() }
        }
    }
}
#endif
