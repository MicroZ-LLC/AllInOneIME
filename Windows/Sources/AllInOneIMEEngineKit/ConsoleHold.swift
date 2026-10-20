#if os(Windows)
import AllInOneIMECore
import Foundation
import WinSDK

/// A console window that stays open once its program has ended, as the Mac's Terminal keeps its window: the console
/// windows the engine opens (`@agent`, a `terminal` command: `WindowsSystem.launchInTerminal`) are this program's own,
/// started in a console of its own (`option`, `CREATE_NEW_CONSOLE`), which starts the program there with the same
/// application and command line (`ConsoleCommand`: still no shell, the same quoting), waits for it, then says how it
/// ended, its exit code, and waits for a key before the window closes. A `terminal` command's output (`git status`, a
/// script) stays to be read; an agent that fails as it starts (not signed in, Node's error in claude.cmd) shows why.
///
/// What the program is goes in the environment of the console's process, never its command line, so it has the whole
/// 32,767 characters a command line can have (`ConsoleCommand.maxCommandLine`); the variables are gone before the
/// program starts.
public enum ConsoleHold {
    /// The option this program is started with to be the console's.
    public static let option = "--run-in-console"
    static let applicationVariable = "ALLINONEIME_CONSOLE_APPLICATION"
    static let commandLineVariable = "ALLINONEIME_CONSOLE_COMMAND_LINE"
    static let titleVariable = "ALLINONEIME_CONSOLE_TITLE"
    static let promptFileVariable = "ALLINONEIME_CONSOLE_PROMPT_FILE"
    /// All four: none of them goes to a console's process but as this launch sets it.
    static let variables = [applicationVariable, commandLineVariable, titleVariable, promptFileVariable]

    /// `command` in a console window of its own that stays open after it (`run`): `holder`, this program, started
    /// there with `option`, suspended, in `directory`, the right to take the foreground the client gave the engine
    /// given to it (`allowForeground`), then running. `title`: the window's. The console process's id.
    static func start(_ command: ConsoleCommand, title: String, holder: String, directory: URL,
                      allowForeground: (DWORD) -> Void = { _ = AllowSetForegroundWindow($0) }) throws -> DWORD {
        var environment = environment(for: command, title: title)
        var commandLine = Array("\"\(holder)\" \(option)".utf16) + [0]
        var startup = STARTUPINFOW()
        startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
        var info = PROCESS_INFORMATION()
        let folder = directory.withUnsafeFileSystemRepresentation { String(cString: $0!) }
        let flags = DWORD(CREATE_NEW_CONSOLE) | DWORD(CREATE_SUSPENDED) | DWORD(CREATE_UNICODE_ENVIRONMENT)
        let ok = holder.withCString(encodedAs: UTF16.self) { application in
            folder.withCString(encodedAs: UTF16.self) { folder in
                environment.withUnsafeMutableBufferPointer { environment in
                    CreateProcessW(application, &commandLine, nil, nil, false, flags, environment.baseAddress, folder, &startup, &info)
                }
            }
        }
        guard ok else { throw SystemActionError("Couldn't open a console window (error \(GetLastError()))") }
        defer {
            CloseHandle(info.hThread)
            CloseHandle(info.hProcess)
        }
        allowForeground(info.dwProcessId)
        guard ResumeThread(info.hThread) != DWORD(bitPattern: -1) else {
            let error = GetLastError()
            TerminateProcess(info.hProcess, 1)
            throw SystemActionError("Couldn't open a console window (error \(error))")
        }
        return info.dwProcessId
    }

    /// The console's process's environment for `command`: this process's, the four variables as this launch sets them.
    /// One this process has itself (the engine's environment is the app's that started it, which may be a console's
    /// process: started from a console's program) never goes on: a prompt's file left over in it would be deleted by a
    /// console that has none.
    static func environment(for command: ConsoleCommand, title: String) -> [WCHAR] {
        var variables = [applicationVariable: command.application, commandLineVariable: command.commandLine, titleVariable: title]
        if let file = command.promptFile { variables[promptFileVariable] = file.withUnsafeFileSystemRepresentation { String(cString: $0!) } }
        return environmentBlock(adding: variables, removing: Self.variables)
    }

    /// This process's environment without `removing` and with `variables` set (`CREATE_UNICODE_ENVIRONMENT`'s block:
    /// "NAME=VALUE" each, NUL after each and one more at the end, in order of the names, the drives' current folders
    /// ("=C:=C:\…") first).
    static func environmentBlock(adding variables: [String: String], removing: [String] = []) -> [WCHAR] {
        var entries: [String] = []
        let gone = Set((Array(variables.keys) + removing).map { $0.uppercased() })
        if let block = GetEnvironmentStringsW() {
            defer { FreeEnvironmentStringsW(block) }
            var at = block
            while at.pointee != 0 {
                let entry = String(decodingCString: at, as: UTF16.self)
                at += entry.utf16.count + 1
                let name = entry.dropFirst().split(separator: "=", maxSplits: 1).first.map { entry.prefix(1) + $0 } ?? Substring(entry)
                if !gone.contains(name.uppercased()) { entries.append(entry) }
            }
        }
        entries += variables.map { "\($0.key)=\($0.value)" }
        func name(_ entry: String) -> String {
            String(entry.dropFirst().split(separator: "=", maxSplits: 1).first.map { entry.prefix(1) + $0 } ?? Substring(entry)).uppercased()
        }
        entries.sort { Array(name($0).utf16).lexicographicallyPrecedes(Array(name($1).utf16)) }
        return entries.flatMap { Array($0.utf16) + [0] } + [0]
    }

    /// The console's process (`AllInOneIMEEngine --run-in-console`): starts the program the environment names in this
    /// console, waits for it, deletes its prompt's file (held open meanwhile, so that `ConsoleCommand.removeStalePrompts`
    /// leaves it), says how it ended and waits for a key. Ctrl+C and Ctrl+Break are the program's: this process stays to
    /// say so. The window closed meanwhile (its X, the terminal's tab), or the user logging off: the program goes with
    /// the console, and so does the prompt's file (the window: the control handler's CTRL_CLOSE_EVENT; logoff and
    /// shutdown: `EndSession`'s window, as a process that loads user32 is never told of them through the handler). Its
    /// exit code: 0 once the key is pressed (the program's is on the screen), 2 without a program.
    public static func run() -> Int32 {
        guard let application = take(applicationVariable), let commandLine = take(commandLineVariable) else { return 2 }
        let title = take(titleVariable)
        let promptFile = take(promptFileVariable)
        // A GUI build (the installed engine) gets no console of its own from CREATE_NEW_CONSOLE: it makes one.
        if GetConsoleWindow() == nil { AllocConsole() }
        let output = open("CONOUT$"), input = open("CONIN$")
        let name = title.flatMap { $0.isEmpty ? nil : $0 } ?? (application as NSString).lastPathComponent
        _ = name.withCString(encodedAs: UTF16.self) { SetConsoleTitleW($0) }
        // The prompt's file, open (to read, no one may delete it) while the program runs.
        let held = promptFile.flatMap { file -> HANDLE? in
            let handle = file.withCString(encodedAs: UTF16.self) {
                CreateFileW($0, GENERIC_READ, DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE), nil, DWORD(OPEN_EXISTING), 0, nil)
            }
            return handle == INVALID_HANDLE_VALUE ? nil : handle
        }
        if let promptFile {
            HeldPrompt.shared.hold(promptFile, handle: held)
            EndSession.watch { HeldPrompt.shared.remove() }
        }
        SetConsoleCtrlHandler({ event in
            switch event {
            case DWORD(CTRL_C_EVENT), DWORD(CTRL_BREAK_EVENT):
                return true  // the program's
            case DWORD(CTRL_CLOSE_EVENT), DWORD(CTRL_LOGOFF_EVENT), DWORD(CTRL_SHUTDOWN_EVENT):
                // The window going (Windows ends this process when the handler returns): the file first. (Logoff and
                // shutdown never come here in this process, which loads user32: `EndSession`.)
                HeldPrompt.shared.remove()
                return false
            default:
                return false
            }
        }, true)

        var message: String
        var commandLineBuffer = Array(commandLine.utf16) + [0]
        var startup = STARTUPINFOW()
        startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
        var info = PROCESS_INFORMATION()
        let started = application.withCString(encodedAs: UTF16.self) {
            CreateProcessW($0, &commandLineBuffer, nil, nil, false, DWORD(CREATE_UNICODE_ENVIRONMENT), nil, nil, &startup, &info)
        }
        let error = GetLastError()
        // Once the program runs: it never waits on the window (a terminal may take a moment to show it, or never say).
        bringToFront()
        if started {
            CloseHandle(info.hThread)
            WaitForSingleObject(info.hProcess, INFINITE)
            var code: DWORD = 0
            GetExitCodeProcess(info.hProcess, &code)
            CloseHandle(info.hProcess)
            message = endMessage(name, code: code)
        } else {
            message = chinese ? "\(name) 没能启动（错误 \(error)）。按任意键关闭此窗口。"
                : "Couldn't start \(name) (error \(error)). Press any key to close this window."
        }
        HeldPrompt.shared.remove()
        write("\r\n" + message, to: output)
        waitForKey(input)
        return 0
    }

    /// The line after the program: its name and exit code (in hexadecimal when it is an NTSTATUS, as 0xC000013A is
    /// for a program closed with Ctrl+C).
    static func endMessage(_ name: String, code: DWORD) -> String {
        let shown = code >= 0x8000_0000 ? "0x" + String(code, radix: 16, uppercase: true) : String(code)
        return chinese ? "[\(name) 已结束，退出码 \(shown)] 按任意键关闭此窗口。"
            : "[\(name) exited with code \(shown)] Press any key to close this window."
    }

    /// Whether Windows speaks Chinese to the user (`GetUserDefaultUILanguage`).
    static var chinese: Bool { GetUserDefaultUILanguage() & 0x3FF == 0x04 }

    /// The console's window to the front, and the right to take the foreground this process was given passed on to
    /// what draws it: conhost.exe's window, or, with Windows Terminal as the default terminal, the terminal's window,
    /// which owns the pseudo console's window `GetConsoleWindow` gives once it has taken this console (up to 5 s).
    static func bringToFront() {
        let deadline = GetTickCount64() + 5000
        repeat {
            if let window = GetConsoleWindow(), let shown = shownWindow(of: window) {
                handOff(to: shown)
                return
            }
            Sleep(20)
        } while GetTickCount64() < deadline
    }

    /// The right to take the foreground passed on to the process of `shown` (Windows Terminal's), while this process
    /// still has it, then `shown` brought to the front: once the foreground has moved this process may have lost the
    /// right to pass on.
    static func handOff(to shown: HWND, allow: (DWORD) -> Void = { _ = AllowSetForegroundWindow($0) },
                        foreground: (HWND) -> Void = { _ = SetForegroundWindow($0) }) {
        var pid: DWORD = 0
        GetWindowThreadProcessId(shown, &pid)
        if pid != GetCurrentProcessId() { allow(pid) }
        foreground(shown)
    }

    /// The window that shows the console whose window is `console`: itself (conhost's), or the window that owns it if it
    /// is a pseudo console's (Windows Terminal's); nil while a pseudo console has no owner yet.
    static func shownWindow(of console: HWND) -> HWND? {
        var name = [WCHAR](repeating: 0, count: 64)
        GetClassNameW(console, &name, 64)
        guard String(decodingCString: name, as: UTF16.self) == "PseudoConsoleWindow" else { return console }
        guard let owner = GetAncestor(console, UINT(GA_ROOTOWNER)), owner != console else { return nil }
        return owner
    }

    /// Waits for a key to be pressed in the console (not Shift, Ctrl, Alt or the Windows key alone), what was typed
    /// before it dropped.
    static func waitForKey(_ input: HANDLE?) {
        guard let input else { return }
        FlushConsoleInputBuffer(input)
        let modifiers: Set<Int32> = [VK_SHIFT, VK_CONTROL, VK_MENU, VK_LWIN, VK_RWIN, VK_CAPITAL, VK_NUMLOCK, VK_SCROLL]
        var record = INPUT_RECORD()
        var read: DWORD = 0
        while ReadConsoleInputW(input, &record, 1, &read) {
            guard read == 1, record.EventType == WORD(KEY_EVENT) else { continue }
            let key = record.Event.KeyEvent
            if key.bKeyDown.boolValue, !modifiers.contains(Int32(key.wVirtualKeyCode)) { return }
        }
    }

    /// The environment variable `name`, taken out of this process's environment.
    static func take(_ name: String) -> String? {
        name.withCString(encodedAs: UTF16.self) { name -> String? in
            let size = GetEnvironmentVariableW(name, nil, 0)
            guard size > 0 else { return nil }
            var buffer = [WCHAR](repeating: 0, count: Int(size))
            guard GetEnvironmentVariableW(name, &buffer, size) == size - 1 else { return nil }
            SetEnvironmentVariableW(name, nil)
            return String(decodingCString: buffer, as: UTF16.self)
        }
    }

    static func open(_ device: String) -> HANDLE? {
        let handle = device.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, GENERIC_READ | DWORD(GENERIC_WRITE), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE), nil, DWORD(OPEN_EXISTING), 0, nil)
        }
        return handle == INVALID_HANDLE_VALUE ? nil : handle
    }

    static func write(_ text: String, to output: HANDLE?) {
        guard let output else { return }
        var units = Array(text.utf16)
        var written: DWORD = 0
        WriteConsoleW(output, &units, DWORD(units.count), &written, nil)
    }

    /// The prompt's file a console holds, deleted once, by whichever comes first: the program's end, or the console's
    /// control handler (a C function, which has no context of its own) as its window closes.
    /// The session ending (logoff, shutdown), told to a hidden top-level window on a thread of its own
    /// (`WM_ENDSESSION`): a console's control handler gets CTRL_LOGOFF_EVENT and CTRL_SHUTDOWN_EVENT only in a process
    /// that loads neither user32 nor gdi32, which this one does. (A message-only window gets no broadcast.) `ended` runs
    /// there, before Windows ends the process.
    enum EndSession {
        static let className = "AllInOneIME.ConsoleEndSession"
        private static let ended = Locked<(@Sendable () -> Void)?>(initialState: nil)

        static func watch(_ ended: @escaping @Sendable () -> Void) {
            self.ended.withLock { $0 = ended }
            Thread.detachNewThread {
                let instance = GetModuleHandleW(nil)
                let window: HWND? = className.withCString(encodedAs: UTF16.self) { name in
                    var windowClass = WNDCLASSEXW()
                    windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
                    windowClass.lpfnWndProc = { window, message, wParam, lParam in
                        switch message {
                        case UINT(WM_QUERYENDSESSION):
                            return 1  // never in the way
                        case UINT(WM_ENDSESSION):
                            if wParam != 0 { EndSession.ended.withLock { $0 }?() }
                            return 0
                        default:
                            return DefWindowProcW(window, message, wParam, lParam)
                        }
                    }
                    windowClass.hInstance = instance
                    windowClass.lpszClassName = name
                    _ = RegisterClassExW(&windowClass)
                    return CreateWindowExW(0, name, name, DWORD(WS_OVERLAPPED), 0, 0, 0, 0, nil, nil, instance, nil)
                }
                guard window != nil else { return }
                var message = MSG()
                while GetMessageW(&message, nil, 0, 0) {  // (-1 only for a window or range that is wrong)
                    TranslateMessage(&message)
                    DispatchMessageW(&message)
                }
            }
        }
    }

    final class HeldPrompt: @unchecked Sendable {
        static let shared = HeldPrompt()
        private let lock = NSLock()
        private var path: String?
        private var handle: HANDLE?

        func hold(_ path: String, handle: HANDLE?) {
            lock.lock()
            (self.path, self.handle) = (path, handle)
            lock.unlock()
        }

        /// Closes the file (this process's hold on it) and deletes it.
        func remove() {
            lock.lock()
            let (path, handle) = (self.path, self.handle)
            (self.path, self.handle) = (nil, nil)
            lock.unlock()
            if let handle { CloseHandle(handle) }
            if let path { _ = path.withCString(encodedAs: UTF16.self) { DeleteFileW($0) } }
        }
    }
}
#endif
