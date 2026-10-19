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

    /// `command` in a console window of its own that stays open after it (`run`): `holder`, this program, started
    /// there with `option`, suspended, in `directory`, the right to take the foreground the client gave the engine
    /// given to it (`allowForeground`), then running. `title`: the window's. The console process's id.
    static func start(_ command: ConsoleCommand, title: String, holder: String, directory: URL,
                      allowForeground: (DWORD) -> Void = { _ = AllowSetForegroundWindow($0) }) throws -> DWORD {
        var variables = [applicationVariable: command.application, commandLineVariable: command.commandLine, titleVariable: title]
        if let file = command.promptFile { variables[promptFileVariable] = file.withUnsafeFileSystemRepresentation { String(cString: $0!) } }
        var environment = environmentBlock(adding: variables)
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

    /// This process's environment with `variables` set (`CREATE_UNICODE_ENVIRONMENT`'s block: "NAME=VALUE" each, NUL
    /// after each and one more at the end, in order of the names, the drives' current folders ("=C:=C:\…") first).
    static func environmentBlock(adding variables: [String: String]) -> [WCHAR] {
        var entries: [String] = []
        if let block = GetEnvironmentStringsW() {
            defer { FreeEnvironmentStringsW(block) }
            var at = block
            while at.pointee != 0 {
                let entry = String(decodingCString: at, as: UTF16.self)
                at += entry.utf16.count + 1
                let name = entry.dropFirst().split(separator: "=", maxSplits: 1).first.map { entry.prefix(1) + $0 } ?? Substring(entry)
                if !variables.keys.contains(where: { $0.uppercased() == name.uppercased() }) { entries.append(entry) }
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
    /// say so. Its exit code: 0 once the key is pressed (the program's is on the screen), 2 without a program.
    public static func run() -> Int32 {
        guard let application = take(applicationVariable), let commandLine = take(commandLineVariable) else { return 2 }
        let title = take(titleVariable)
        let promptFile = take(promptFileVariable)
        // A GUI build (the installed engine) gets no console of its own from CREATE_NEW_CONSOLE: it makes one.
        if GetConsoleWindow() == nil { AllocConsole() }
        let output = open("CONOUT$"), input = open("CONIN$")
        let name = title.flatMap { $0.isEmpty ? nil : $0 } ?? (application as NSString).lastPathComponent
        _ = name.withCString(encodedAs: UTF16.self) { SetConsoleTitleW($0) }
        SetConsoleCtrlHandler({ event in WindowsBool(event == DWORD(CTRL_C_EVENT) || event == DWORD(CTRL_BREAK_EVENT)) }, true)
        // The prompt's file, open (to read, no one may delete it) while the program runs.
        let held = promptFile.flatMap { file -> HANDLE? in
            let handle = file.withCString(encodedAs: UTF16.self) {
                CreateFileW($0, GENERIC_READ, DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE), nil, DWORD(OPEN_EXISTING), 0, nil)
            }
            return handle == INVALID_HANDLE_VALUE ? nil : handle
        }
        bringToFront()

        var message: String
        var commandLineBuffer = Array(commandLine.utf16) + [0]
        var startup = STARTUPINFOW()
        startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
        var info = PROCESS_INFORMATION()
        let started = application.withCString(encodedAs: UTF16.self) {
            CreateProcessW($0, &commandLineBuffer, nil, nil, false, DWORD(CREATE_UNICODE_ENVIRONMENT), nil, nil, &startup, &info)
        }
        if started {
            CloseHandle(info.hThread)
            WaitForSingleObject(info.hProcess, INFINITE)
            var code: DWORD = 0
            GetExitCodeProcess(info.hProcess, &code)
            CloseHandle(info.hProcess)
            message = endMessage(name, code: code)
        } else {
            message = chinese ? "\(name) 没能启动（错误 \(GetLastError())）。按任意键关闭此窗口。"
                : "Couldn't start \(name) (error \(GetLastError())). Press any key to close this window."
        }
        if let held { CloseHandle(held) }
        if let promptFile { _ = promptFile.withCString(encodedAs: UTF16.self) { DeleteFileW($0) } }
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
                var pid: DWORD = 0
                GetWindowThreadProcessId(shown, &pid)
                SetForegroundWindow(shown)
                if pid != GetCurrentProcessId() { AllowSetForegroundWindow(pid) }
                return
            }
            Sleep(20)
        } while GetTickCount64() < deadline
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
}
#endif
