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
    /// Runs `argv` in a new console window, where the user sees and answers it.
    func launchInTerminal(_ argv: [String]) throws
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
        // The client gave the engine the right to take the foreground (`allowForeground`): it goes on to what opens.
        AllowSetForegroundWindow(DWORD(bitPattern: -1))  // ASFW_ANY
        let result = target.withCString(encodedAs: UTF16.self) { file in
            "open".withCString(encodedAs: UTF16.self) { verb in
                ShellExecuteW(nil, verb, file, nil, nil, SW_SHOWNORMAL)
            }
        }
        // ShellExecuteW's result is a number above 32 when it worked.
        guard Int(bitPattern: UnsafeRawPointer(result)) > 32 else {
            throw SystemActionError("Couldn't open \(target) (error \(Int(bitPattern: UnsafeRawPointer(result))))")
        }
    }

    /// In Windows PowerShell's console, which runs the program with its arguments as they are: they go to it encoded
    /// (`-EncodedCommand`, UTF-16 in Base64), each in single quotes, so no character in a prompt is the shell's.
    public func launchInTerminal(_ argv: [String]) throws {
        guard let program = argv.first, !program.isEmpty else { throw SystemActionError("No program to run") }
        let quoted = argv.map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" }
        let script = "& " + quoted.joined(separator: " ")
        let encoded = Data(script.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }).base64EncodedString()
        let system = Self.systemFolder
        let powershell = system + #"\WindowsPowerShell\v1.0\powershell.exe"#
        var commandLine = Array(("\"\(powershell)\" -NoLogo -NoExit -ExecutionPolicy Bypass -EncodedCommand \(encoded)").utf16) + [0]
        var startup = STARTUPINFOW()
        startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
        var info = PROCESS_INFORMATION()
        AllowSetForegroundWindow(DWORD(bitPattern: -1))  // ASFW_ANY
        let ok = powershell.withCString(encodedAs: UTF16.self) { application in
            CreateProcessW(application, &commandLine, nil, nil, false, DWORD(CREATE_NEW_CONSOLE | CREATE_UNICODE_ENVIRONMENT), nil,
                           nil, &startup, &info)
        }
        guard ok else { throw SystemActionError("Couldn't start a terminal window (error \(GetLastError()))") }
        CloseHandle(info.hThread)
        CloseHandle(info.hProcess)
    }

    static var systemFolder: String {
        var buffer = [WCHAR](repeating: 0, count: Int(MAX_PATH))
        let count = GetSystemDirectoryW(&buffer, UINT(buffer.count))
        return count > 0 ? String(decoding: buffer.prefix(Int(count)), as: UTF16.self) : #"C:\Windows\System32"#
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
            fm.fileExists(atPath: text, isDirectory: &isFolder)
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
