import AllInOneIMECore
import Foundation
#if os(Windows)
import WinSDK
#endif

/// What the engine does to the system for a Composer's effects (§6 "What the engine does itself"): the clipboard,
/// opening an address or a file, a program in a terminal window, finding files and apps for `@open`. Windows' own in
/// the engine (`WindowsSystem`); the tests record them instead.
public protocol SystemActions: Sendable {
    /// Puts `text` on the clipboard.
    func copy(_ text: String) -> Bool
    /// The clipboard's text, if it has some.
    func readClipboard() -> String?
    /// Opens a web address in the default browser, or a file, folder or program as Explorer would.
    func open(_ target: String) throws
    /// Runs `argv` in a new console window, where the user sees and answers it, with `prompt` (an agent's first
    /// message) as its last argument when there is one.
    func launchInTerminal(_ argv: [String], prompt: String?) throws
    /// Files and apps named like `query` (`@open`).
    func search(_ query: String) -> [SearchResult]
}

public struct SystemActionError: Error, LocalizedError, Equatable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

#if os(Windows)

/// Windows' clipboard (CF_UNICODETEXT), ShellExecuteW, a console window for a terminal command, and `@open`'s search
/// over the Start menu and the user's own folders.
public struct WindowsSystem: SystemActions {
    public init() {}

    public func copy(_ text: String) -> Bool {
        guard openClipboard() else { return false }
        defer { CloseClipboard() }
        EmptyClipboard()
        let units = Array(text.utf16) + [0]
        guard let memory = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(units.count * 2)) else { return false }
        guard let pointer = GlobalLock(memory) else { GlobalFree(memory); return false }
        units.withUnsafeBytes { pointer.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        GlobalUnlock(memory)
        guard SetClipboardData(UINT(CF_UNICODETEXT), memory) != nil else { GlobalFree(memory); return false }
        return true
    }

    public func readClipboard() -> String? {
        guard IsClipboardFormatAvailable(UINT(CF_UNICODETEXT)), openClipboard() else { return nil }
        defer { CloseClipboard() }
        guard let memory = GetClipboardData(UINT(CF_UNICODETEXT)), let pointer = GlobalLock(memory) else { return nil }
        defer { GlobalUnlock(memory) }
        let text = String(decodingCString: pointer.assumingMemoryBound(to: UInt16.self), as: UTF16.self)
        return text.isEmpty ? nil : text
    }

    /// The clipboard is one at a time across the system: tried for a moment while another program has it open.
    private func openClipboard() -> Bool {
        for _ in 0..<10 {
            if OpenClipboard(nil) { return true }
            Sleep(20)
        }
        return false
    }

    public func open(_ target: String) throws {
        try Self.shellOpen(target)
    }

    /// `ShellExecuteExW`'s "open", as Explorer opens what is double-clicked. The client gave the engine the right to
    /// take the foreground (`allowForeground`); it goes to the process that opens `target` when one is started (a
    /// browser, an editor), and to no other: there is no starting it suspended through the shell, so it is given right
    /// after (programs take longer than that to show a window). The process's id, if one was started.
    @discardableResult
    static func shellOpen(_ target: String) throws -> DWORD? {
        var info = SHELLEXECUTEINFOW()
        info.cbSize = DWORD(MemoryLayout<SHELLEXECUTEINFOW>.size)
        // No dialog of the shell's ("Windows can't find…"): it would wait for a click, and a failure is a notice.
        info.fMask = ULONG(SEE_MASK_NOCLOSEPROCESS) | ULONG(SEE_MASK_NOASYNC) | ULONG(SEE_MASK_FLAG_NO_UI)
        info.nShow = SW_SHOWNORMAL
        let ok = target.withCString(encodedAs: UTF16.self) { file in
            "open".withCString(encodedAs: UTF16.self) { verb in
                info.lpVerb = verb
                info.lpFile = file
                return ShellExecuteExW(&info)
            }
        }
        guard ok else { throw SystemActionError("Couldn't open \(target) (error \(GetLastError()))") }
        guard let process = info.hProcess else { return nil }  // opened by a program already running (DDE, COM)
        defer { CloseHandle(process) }
        let pid = GetProcessId(process)
        AllowSetForegroundWindow(pid)
        return pid
    }

    /// In a console window of its own, started directly, with no shell in between (`ConsoleCommand`: the program found
    /// on the PATH, its arguments quoted for it, a batch file's escaped for cmd.exe, a prompt too long for the command
    /// line in a file), in the user's home folder. Started suspended: the right to take the foreground the client gave
    /// the engine (`allowForeground`) goes to that one process, then it runs.
    public func launchInTerminal(_ argv: [String], prompt: String?) throws {
        let path = WindowsPrograms.variable("PATH", in: ProcessInfo.processInfo.environment)
        let command = try ConsoleCommand.make(argv, prompt: prompt, path: path, promptFolder: ConsoleCommand.defaultPromptFolder)
        do {
            try Self.start(command, flags: DWORD(CREATE_NEW_CONSOLE))
        } catch {
            if let file = command.promptFile { try? FileManager.default.removeItem(at: file) }
            throw error
        }
    }

    /// Starts `command` suspended (with `flags`: a console of its own), lets it take the foreground, then lets it run.
    /// Its process id.
    @discardableResult
    static func start(_ command: ConsoleCommand, flags: DWORD) throws -> DWORD {
        var commandLine = Array(command.commandLine.utf16) + [0]
        var startup = STARTUPINFOW()
        startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
        var info = PROCESS_INFORMATION()
        let home = CorePaths.home.withUnsafeFileSystemRepresentation { String(cString: $0!) }
        let ok = command.application.withCString(encodedAs: UTF16.self) { application in
            home.withCString(encodedAs: UTF16.self) { home in
                CreateProcessW(application, &commandLine, nil, nil, false, flags | DWORD(CREATE_SUSPENDED) | DWORD(CREATE_UNICODE_ENVIRONMENT),
                               nil, home, &startup, &info)
            }
        }
        guard ok else { throw SystemActionError("Couldn't start \(command.application) (error \(GetLastError()))") }
        defer {
            CloseHandle(info.hThread)
            CloseHandle(info.hProcess)
        }
        AllowSetForegroundWindow(info.dwProcessId)
        guard ResumeThread(info.hThread) != DWORD(bitPattern: -1) else {
            let error = GetLastError()
            TerminateProcess(info.hProcess, 1)
            throw SystemActionError("Couldn't start \(command.application) (error \(error))")
        }
        return info.dwProcessId
    }

    public func search(_ query: String) -> [SearchResult] { FileSearch.search(query) }
}

#endif

/// `@open` on Windows: an address or a path as typed, else the Start menu's programs (their shortcuts) and the files
/// and folders on the user's Desktop and in Documents and Downloads whose names hold what is typed, names that start
/// with it first. A plain walk over a few folders, not an index: up to `limit`.
public enum FileSearch {
    public static func search(_ query: String, limit: Int = 20,
                              environment: [String: String] = ProcessInfo.processInfo.environment) -> [SearchResult] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let fm = FileManager.default
        var results: [SearchResult] = []
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            results.append(SearchResult(name: text, path: text))
        } else if text.contains(".") && !text.contains(" ") && !text.contains("\\") && !text.contains("/") && text.count > 3,
                  text.split(separator: ".").count >= 2, !fm.fileExists(atPath: text) {
            results.append(SearchResult(name: text, path: "https://" + text))
        }
        if CorePaths.isAbsolute(text), fm.fileExists(atPath: text) {
            var isFolder: ObjCBool = false
            _ = fm.fileExists(atPath: text, isDirectory: &isFolder)
            results.append(SearchResult(name: (text as NSString).lastPathComponent, path: text, isFolder: isFolder.boolValue))
        }
        let needle = text.lowercased()
        var found: [(rank: Int, result: SearchResult)] = []
        var seen = Set<String>()
        func consider(_ url: URL, isFolder: Bool) {
            var name = url.lastPathComponent
            if name.lowercased().hasSuffix(".lnk") || name.lowercased().hasSuffix(".url") { name = String(name.dropLast(4)) }
            let lower = name.lowercased()
            guard lower.contains(needle), seen.insert(lower + "\u{0}" + url.path).inserted else { return }
            found.append((lower.hasPrefix(needle) ? 0 : 1, SearchResult(name: name, path: url.path, isFolder: isFolder)))
        }
        func walk(_ folder: URL, depth: Int) {
            guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles]) else { return }
            for item in items {
                let isFolder = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                consider(item, isFolder: isFolder)
                if isFolder, depth > 1 { walk(item, depth: depth - 1) }
            }
        }
        let home = CorePaths.home
        let startMenus = [environment["APPDATA"], environment["ProgramData"]].compactMap { $0 }
            .map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("Microsoft/Windows/Start Menu/Programs") }
        for folder in startMenus { walk(folder, depth: 3) }
        for name in ["Desktop", "Documents", "Downloads"] { walk(home.appendingPathComponent(name, isDirectory: true), depth: 1) }
        found.sort { ($0.rank, $0.result.name.count) < ($1.rank, $1.result.name.count) }
        results += found.prefix(max(limit - results.count, 0)).map(\.result)
        return results
    }
}
