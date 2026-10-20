import AllInOneIMECore
import Foundation
#if os(Windows)
import WinSDK
#endif

/// What the engine does to the system for a Composer's effects (§6 "What the engine does itself"): the clipboard,
/// opening an address or a file, a program in a terminal window, finding files and apps for `@open`. Windows' own in
/// the engine (`WindowsSystem`); the tests record them instead. The clipboard is used on the clipboard's queue, opening
/// and terminals on the system queue (`SystemQueue`: the shell's thread), `search`, which walks folders, on a thread of
/// its own.
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
    /// Starts the program at `program` with `arguments`, in the foreground (the Settings app).
    func start(_ program: String, arguments: [String]) throws
}

extension SystemActions {
    /// Opened as a file is, without arguments.
    public func start(_ program: String, arguments: [String]) throws { try open(program) }
}

/// Where the engine uses `SystemActions`: threads of its own (`SystemThread` on Windows: the shell's, the clipboard's),
/// never a session's queue nor a key's way (§5.4). What comes of it goes back to the session through
/// `ComposerSession.feed`.
public protocol SystemQueue: Sendable {
    func async(_ work: @escaping @Sendable () -> Void)
}

/// A serial dispatch queue: the system queue off Windows (for trying the engine out).
public struct SerialSystemQueue: SystemQueue {
    private let queue = DispatchQueue(label: "AllInOneIME system")
    public init() {}
    public func async(_ work: @escaping @Sendable () -> Void) { queue.async(execute: work) }
}

public struct SystemActionError: Error, LocalizedError, Equatable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

#if os(Windows)

/// Windows' clipboard (CF_UNICODETEXT), ShellExecuteExW, a console window for a terminal command, and `@open`'s search
/// over the Start menu and the user's own folders. The clipboard runs on the engine's clipboard thread (`clipboard`),
/// opening and consoles on its shell thread (`shell`), whoever calls them: the shell wants its COM apartment and may
/// keep it tens of seconds, and the clipboard is the clipboard thread's message-only window's (`SystemThread.window`),
/// whose `WM_DESTROYCLIPBOARD` another program's Ctrl+C waits on, so nothing slow ever runs there.
public struct WindowsSystem: SystemActions {
    /// The clipboard's thread: only what is quick.
    public let clipboard: SystemThread
    /// The shell's thread: `ShellExecuteExW`, `CreateProcessW`.
    public let shell: SystemThread
    /// Marks what is copied as not for the clipboard's history and the cloud clipboard
    /// ("ExcludeClipboardContentFromMonitorProcessing"): for the tests, which put the user's clipboard back after.
    var excludedFromHistory = false

    /// This program, which a console window's process is (`ConsoleHold`).
    public let holder: String

    public init(clipboard: SystemThread, shell: SystemThread, holder: String) {
        self.clipboard = clipboard
        self.shell = shell
        self.holder = holder
    }

    /// The clipboard's owner is the clipboard thread's window: `SetClipboardData` fails on a clipboard opened without
    /// one (`OpenClipboard(NULL)`, then `EmptyClipboard`: the owner is NULL), and another program emptying it sends the
    /// owner `WM_DESTROYCLIPBOARD`, which that thread's message loop answers at once.
    public func copy(_ text: String) -> Bool {
        clipboard.sync { [excludedFromHistory, clipboard] in
            guard let window = clipboard.window, Self.openClipboard(window) else { return false }
            defer { CloseClipboard() }
            guard EmptyClipboard(), Self.set(UINT(CF_UNICODETEXT), Data(bytes: Array(text.utf16) + [0], count: (text.utf16.count + 1) * 2)) else {
                return false
            }
            if excludedFromHistory { Self.excludeFromHistory() }
            return true
        }
    }

    public func readClipboard() -> String? {
        clipboard.sync { [clipboard] in
            guard IsClipboardFormatAvailable(UINT(CF_UNICODETEXT)), let window = clipboard.window, Self.openClipboard(window) else {
                return nil
            }
            defer { CloseClipboard() }
            guard let memory = GetClipboardData(UINT(CF_UNICODETEXT)), let pointer = GlobalLock(memory) else { return nil }
            defer { GlobalUnlock(memory) }
            let text = String(decodingCString: pointer.assumingMemoryBound(to: UInt16.self), as: UTF16.self)
            return text.isEmpty ? nil : text
        }
    }

    /// The clipboard is one at a time across the system: tried for a moment while another program has it open.
    static func openClipboard(_ owner: HWND) -> Bool {
        for _ in 0..<10 {
            if OpenClipboard(owner) { return true }
            Sleep(20)
        }
        return false
    }

    /// `data` on the open clipboard as `format`.
    static func set(_ format: UINT, _ data: Data) -> Bool {
        guard let memory = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(max(data.count, 1))) else { return false }
        guard let pointer = GlobalLock(memory) else {
            GlobalFree(memory)
            return false
        }
        data.withUnsafeBytes { if let base = $0.baseAddress { pointer.copyMemory(from: base, byteCount: $0.count) } }
        GlobalUnlock(memory)
        guard SetClipboardData(format, memory) != nil else {
            GlobalFree(memory)
            return false
        }
        return true
    }

    /// On the open clipboard: kept out of the clipboard's history and the cloud clipboard.
    static func excludeFromHistory() {
        let format = "ExcludeClipboardContentFromMonitorProcessing".withCString(encodedAs: UTF16.self) { RegisterClipboardFormatW($0) }
        if format != 0 { _ = set(format, Data([0, 0, 0, 0])) }
    }

    public func open(_ target: String) throws {
        _ = try shell.syncThrowing { try Self.shellOpen(target) }
    }

    /// What `shellOpen` did: the process the shell started to open what it was given (nil when a program already
    /// running took it, by DDE or COM: a browser, Explorer), and the processes given the right to take the foreground,
    /// in that order.
    struct Opened: Equatable {
        var started: DWORD?
        var allowed: [DWORD]
    }

    /// `ShellExecuteExW`'s "open", as Explorer opens what is double-clicked. The client gave the engine the right to
    /// take the foreground (`allowForeground`); it goes on to what shows `target`, and to no other process (never
    /// `ASFW_ANY`):
    /// - first to the program already running that the shell may hand it to (`runningHandler`: the browser for an
    ///   address, Explorer for a folder, as `@settings` opens one), before the shell asks it, as it takes the foreground
    ///   then;
    /// - then to the process the shell started, if it started one (there is no starting it suspended through the
    ///   shell, so it is given right after: programs take longer than that to show a window).
    ///
    /// `parameters`: a program's arguments, as its command line takes them (`start`).
    @discardableResult
    static func shellOpen(_ target: String, parameters: String? = nil, handler: (String) -> DWORD? = runningHandler,
                          allowForeground: (DWORD) -> Void = { _ = AllowSetForegroundWindow($0) }) throws -> Opened {
        var opened = Opened(started: nil, allowed: [])
        if let running = handler(target) {
            allowForeground(running)
            opened.allowed.append(running)
        }
        var info = SHELLEXECUTEINFOW()
        info.cbSize = DWORD(MemoryLayout<SHELLEXECUTEINFOW>.size)
        // No dialog of the shell's ("Windows can't find…"): it would wait for a click, and a failure is a notice.
        info.fMask = ULONG(SEE_MASK_NOCLOSEPROCESS) | ULONG(SEE_MASK_NOASYNC) | ULONG(SEE_MASK_FLAG_NO_UI)
        info.nShow = SW_SHOWNORMAL
        let ok = target.withCString(encodedAs: UTF16.self) { file in
            "open".withCString(encodedAs: UTF16.self) { verb in
                (parameters ?? "").withCString(encodedAs: UTF16.self) { arguments in
                    info.lpVerb = verb
                    info.lpFile = file
                    info.lpParameters = parameters == nil ? nil : arguments
                    return ShellExecuteExW(&info)
                }
            }
        }
        guard ok else { throw SystemActionError("Couldn't open \(target) (error \(GetLastError()))") }
        guard let process = info.hProcess else { return opened }  // opened by a program already running (DDE, COM)
        defer { CloseHandle(process) }
        let pid = GetProcessId(process)
        allowForeground(pid)
        opened.started = pid
        opened.allowed.append(pid)
        return opened
    }

    /// Starts `program` with `arguments` as `open` opens a file, on the shell's thread: the right to take the foreground
    /// goes to the program's own window already on the screen, if it has one (a second start hands over to the first
    /// and quits, as the Settings app does), then to the process started, and to no other.
    public func start(_ program: String, arguments: [String]) throws {
        let parameters = arguments.isEmpty ? nil : Self.commandLine(arguments)
        _ = try shell.syncThrowing { try Self.shellOpen(program, parameters: parameters, handler: Self.windowProcess(image:)) }
    }

    /// Arguments as a program's command line takes them: one that is empty or has a space or a quote in quotes, its
    /// quotes escaped.
    static func commandLine(_ arguments: [String]) -> String {
        arguments.map { argument in
            argument.isEmpty || argument.contains(" ") || argument.contains("\"")
                ? "\"" + argument.replacingOccurrences(of: "\"", with: "\\\"") + "\"" : argument
        }.joined(separator: " ")
    }

    /// The program already running that the shell would hand `target` to (`handlerExecutable`), if a process of it
    /// in this session has a window on the screen: the one nearest the top.
    static func runningHandler(for target: String) -> DWORD? {
        handlerExecutable(for: target).flatMap(windowProcess(image:))
    }

    /// The program that opens `target`: Explorer for a folder; for an address, its scheme's program (the default
    /// browser's for https); for a file, its type's (`AssocQueryStringW`). Nil when there is none to tell.
    static func handlerExecutable(for target: String) -> String? {
        var isFolder: ObjCBool = false
        if CorePaths.isAbsolute(target), FileManager.default.fileExists(atPath: target, isDirectory: &isFolder), isFolder.boolValue {
            var windows = [WCHAR](repeating: 0, count: Int(MAX_PATH))
            let count = Int(GetWindowsDirectoryW(&windows, UINT(MAX_PATH)))
            return count > 0 ? String(decoding: windows.prefix(count), as: UTF16.self) + #"\explorer.exe"# : nil
        }
        let association: String, flags: ASSOCF
        if let scheme = URL(string: target)?.scheme, scheme.count > 1, !CorePaths.isAbsolute(target) {
            (association, flags) = (scheme, ASSOCF(ASSOCF_IS_PROTOCOL))
        } else {
            let type = (target as NSString).pathExtension
            guard !type.isEmpty else { return nil }
            (association, flags) = ("." + type, ASSOCF(0))
        }
        var size: DWORD = DWORD(MAX_PATH) * 2
        var buffer = [WCHAR](repeating: 0, count: Int(size))
        let found = association.withCString(encodedAs: UTF16.self) { association in
            "open".withCString(encodedAs: UTF16.self) { verb in
                AssocQueryStringW(flags, ASSOCSTR_EXECUTABLE, association, verb, &buffer, &size)
            }
        }
        guard found == S_OK else { return nil }
        let executable = String(decodingCString: buffer, as: UTF16.self)
        return executable.lowercased().hasSuffix(".exe") ? executable : nil
    }

    /// The process of this session whose image is `image` (a full path, in any case) with a visible window of its own
    /// on top level, the one nearest the top (`EnumWindows` goes in z-order).
    static func windowProcess(image: String) -> DWORD? {
        final class Hunt {
            var image = ""
            var session: DWORD = 0
            var seen: Set<DWORD> = []
            var found: DWORD?
        }
        let hunt = Hunt()
        hunt.image = image
        ProcessIdToSessionId(GetCurrentProcessId(), &hunt.session)
        EnumWindows({ window, context in
            let hunt = Unmanaged<Hunt>.fromOpaque(UnsafeRawPointer(bitPattern: Int(context))!).takeUnretainedValue()
            // WS_VISIBLE: IsWindowVisible asks too whether the desktop is shown, which a service session's isn't.
            guard let window, GetWindowLongPtrW(window, GWL_STYLE) & LONG_PTR(WS_VISIBLE) != 0,
                  GetWindow(window, UINT(GW_OWNER)) == nil else { return true }
            var pid: DWORD = 0, session: DWORD = 0
            GetWindowThreadProcessId(window, &pid)
            guard pid != 0, hunt.seen.insert(pid).inserted, ProcessIdToSessionId(pid, &session), session == hunt.session,
                  let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) else { return true }
            defer { CloseHandle(process) }
            var path = [WCHAR](repeating: 0, count: 1024)
            var size = DWORD(path.count)
            guard QueryFullProcessImageNameW(process, 0, &path, &size) else { return true }
            let found = String(decoding: path.prefix(Int(size)), as: UTF16.self)
            guard found.compare(hunt.image, options: .caseInsensitive) == .orderedSame else { return true }
            hunt.found = pid
            return false
        }, LPARAM(Int(bitPattern: Unmanaged.passUnretained(hunt).toOpaque())))
        return hunt.found
    }

    /// In a console window of its own that stays open after the program ends (`ConsoleHold`), started directly, with
    /// no shell in between (`ConsoleCommand`: the program found on the PATH, its arguments quoted for it, a batch file's
    /// escaped for cmd.exe, a prompt too long for the command line in a file), in the user's home folder. The console's
    /// process is started suspended: the right to take the foreground the client gave the engine (`allowForeground`)
    /// goes to that one process, then it runs.
    public func launchInTerminal(_ argv: [String], prompt: String?) throws {
        _ = try shell.syncThrowing { try startInConsole(argv, prompt: prompt) }
    }

    /// `launchInTerminal`, on the calling thread (`path`, `promptFolder`: the PATH's, `%TEMP%\AllInOneIME`, unless
    /// given): the console's process's id.
    func startInConsole(_ argv: [String], prompt: String?, path: String? = nil, promptFolder: URL? = nil) throws -> DWORD {
        let path = path ?? WindowsPrograms.variable("PATH", in: ProcessInfo.processInfo.environment)
        let command = try ConsoleCommand.make(argv, prompt: prompt, path: path, directory: CorePaths.home,
                                              promptFolder: promptFolder ?? ConsoleCommand.defaultPromptFolder)
        do {
            return try ConsoleHold.start(command, title: argv.first ?? "", holder: holder, directory: CorePaths.home)
        } catch {
            if let file = command.promptFile { try? FileManager.default.removeItem(at: file) }
            throw error
        }
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
