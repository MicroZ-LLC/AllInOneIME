#if os(Windows)
import Foundation
import WinSDK

/// How Windows finds a program and what starts it, for the core (`CommandRunner.resolve`, `AWSProcessRunner.resolve`,
/// `ScriptCommand.launch`, `WindowsProcessLauncher`). Windows has no executable bit and no "#!": a file runs by its
/// extension. Here, as in cmd.exe:
///
/// - a bare name is looked for in PATH's folders (split on ";", those written in full only), with PATHEXT's extensions
///   (".COM;.EXE;.BAT;.CMD;…"), never in the current folder (cmd.exe looks there first: a program planted where a
///   command runs isn't taken);
/// - a .exe or .com starts itself; a .bat or .cmd through cmd.exe, its arguments escaped (`WindowsCommandLine.batch`);
/// - a script through its interpreter: .ps1 with PowerShell, .py with the Python launcher (py, else python), .vbs and
///   the other Windows Script Host files with cscript, .sh and a file whose first line is "#!" with Git Bash's bash when
///   it is installed (a "#!" line names the interpreter: sh and bash are Git Bash's, python the Python launcher's, any
///   other one found on the PATH or among Git's tools).
///
/// Public for the Windows shell, which starts a program in a console window of its own the same way (`@agent`).
public enum WindowsPrograms {
    /// What a file is, as far as starting it goes.
    public enum Kind: Equatable {
        /// A Windows program: .exe, .com, or another file that is one (it starts with "MZ").
        case program
        /// .bat, .cmd: through cmd.exe.
        case batch
        /// .ps1: through PowerShell.
        case powerShell
        /// .py, .pyw: through the Python launcher.
        case python
        /// .vbs, .vbe, .js, .jse, .wsf, .wsh without a "#!" line: through cscript.
        case windowsScript
        /// .sh without a "#!" line: through Git Bash.
        case shell
        /// A file whose first line is "#!": its words, the interpreter first.
        case shebang([String])
    }

    /// What `CreateProcessW` is given: the program it starts (a full path, "C:\…") and the command line it hands that
    /// program, from which it reads its arguments.
    public struct Invocation: Equatable {
        public var application: String
        public var commandLine: String
    }

    // MARK: Finding a program

    /// `program` as it will be started: a name without a folder is looked for in `path`'s folders, a path is taken as
    /// written (relative to `directory`, or to the current folder when there is none; "~" is the home folder only when
    /// `expandingTilde`). Either is the file itself when it is one Windows runs or a script whose kind is known
    /// (`kind(of:)`), else the first that is with one of PATHEXT's extensions added ("git" → "git.exe"). Nil when none is.
    public static func find(_ program: String, path: String?, directory: URL? = nil, expandingTilde: Bool = false) -> URL? {
        guard !program.isEmpty, !program.contains("\0") else { return nil }
        let extensions = executableExtensions()
        if program.contains(where: CorePaths.isSeparator) || hasDrive(program) {
            var text = program
            if expandingTilde, text == "~" || text.hasPrefix("~/") || text.hasPrefix(#"~\"#) {
                text = CorePaths.home.path + text.dropFirst()
            }
            let rooted = CorePaths.isAbsolute(text) || hasDrive(text) || text.first.map(CorePaths.isSeparator) == true
            guard let directory, !rooted else { return runnable(URL(fileURLWithPath: text), extensions) }
            return runnable(directory.appendingPathComponent(text), extensions)
        }
        for folder in folders(inPath: path) {
            if let found = runnable(URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent(program), extensions) {
                return found
            }
        }
        return nil
    }

    /// PATH's folders in order: split on ";", quotes dropped, and only those written in full (`isFullyQualified`: "C:\…",
    /// "\\server\share\…"). One that isn't (".", "bin", "C:bin", "\bin", "/usr/bin") is a folder of wherever the input
    /// method or the program runs, on whichever drive: a program planted there isn't taken, as cmd.exe's current folder
    /// isn't. A ":" that isn't a drive's ("C:") splits too, so that a list written the POSIX way ("C:/Users/me/bin:C:/tools")
    /// still reads (no Windows path has one anywhere else).
    static func folders(inPath path: String?) -> [String] {
        var folders: [String] = []
        for entry in (path ?? "").split(separator: ";") {
            var part = ""
            for character in entry where character != "\"" {
                if character == ":", !isDrivePrefix(part) {
                    folders.append(part)
                    part = ""
                } else {
                    part.append(character)
                }
            }
            folders.append(part)
        }
        return folders.filter(isFullyQualified)
    }

    /// Whether `folder` is written in full, the same wherever it is read from: a drive and its root ("C:\…", "C:/…"),
    /// or a share or a device's namespace ("\\server\share\…", "\\?\C:\…").
    static func isFullyQualified(_ folder: String) -> Bool {
        let start = Array(folder.prefix(3))
        guard start.count == 3 else { return false }
        if start[0].isASCII, start[0].isLetter, start[1] == ":", CorePaths.isSeparator(start[2]) { return true }
        return CorePaths.isSeparator(start[0]) && CorePaths.isSeparator(start[1]) && !CorePaths.isSeparator(start[2])
    }

    /// PATHEXT's extensions, lowercased, in its order (".com", ".exe", ".bat", ".cmd" when it isn't set).
    static func executableExtensions(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        let text = variable("PATHEXT", in: environment) ?? ".COM;.EXE;.BAT;.CMD"
        return text.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { $0.count > 1 && $0.hasPrefix(".") }
    }

    /// `name`'s value in `environment`, its name in any case (Windows' variables are "Path" as much as "PATH").
    public static func variable(_ name: String, in environment: [String: String]) -> String? {
        environment[name] ?? environment.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// `url` when it is a file of a kind that runs (`kind(of:)`); else the first of `url` with one of `extensions`
    /// (PATHEXT's) added that is.
    private static func runnable(_ url: URL, _ extensions: [String]) -> URL? {
        let known = ["exe", "com", "bat", "cmd", "ps1", "py", "pyw", "sh"] + extensions.map { String($0.dropFirst()) }
        let hasExtension = known.contains(url.pathExtension.lowercased())
        // A name with an extension that runs is taken as written first; another ("git", "my.tool") with PATHEXT's first,
        // then as written when it is a script with a "#!" line (or a program without its .exe).
        if hasExtension, kind(of: url) != nil { return url }
        let folder = url.deletingLastPathComponent(), name = url.lastPathComponent
        for suffix in extensions {
            let candidate = folder.appendingPathComponent(name + suffix)
            if kind(of: candidate) != nil { return candidate }
        }
        return !hasExtension && kind(of: url) != nil ? url : nil
    }

    /// "C:x": a path on a drive, from its current folder there.
    private static func hasDrive(_ text: String) -> Bool {
        let start = Array(text.prefix(2))
        return start.count == 2 && start[0].isASCII && start[0].isLetter && start[1] == ":"
    }

    /// Whether `part`, followed by a ":", is a drive: one letter, alone or after "\\?\" or "\\.\".
    private static func isDrivePrefix(_ part: String) -> Bool {
        var letters = Substring(part)
        if part.hasPrefix(#"\\?\"#) || part.hasPrefix(#"\\.\"#) { letters = letters.dropFirst(4) }
        return letters.count == 1 && letters.first!.isASCII && letters.first!.isLetter
    }

    // MARK: What starts a file

    /// What `url` is when it is a file (not a folder) that can be started: by its extension, else by its first bytes
    /// ("#!", "MZ"). Nil for any other file, or none, and for a device's name (`CorePaths.isDeviceName`: "NUL",
    /// "con.bat"), which Windows opens as the device in any folder.
    public static func kind(of url: URL) -> Kind? {
        guard !CorePaths.isDeviceName(Substring(url.lastPathComponent)) else { return nil }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue else { return nil }
        let suffix = url.pathExtension.lowercased()
        switch suffix {
        case "exe", "com": return .program
        case "bat", "cmd": return .batch
        case "ps1": return .powerShell
        case "py", "pyw": return .python
        default: break
        }
        let head = Self.head(of: url)
        if let words = shebang(head) { return .shebang(words) }
        switch suffix {
        case "vbs", "vbe", "js", "jse", "wsf", "wsh": return .windowsScript
        case "sh": return .shell
        default: return head.starts(with: [0x4D, 0x5A]) ? .program : nil
        }
    }

    /// The words of a "#!" line at the start of `head` (after a byte order mark too); nil without one.
    static func shebang(_ head: Data) -> [String]? {
        var line = String(decoding: head.prefix { $0 != 0x0A && $0 != 0x0D }, as: UTF8.self)
        if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
        guard line.hasPrefix("#!") else { return nil }
        let words = line.dropFirst(2).split(whereSeparator: \.isWhitespace).map(String.init)
        return words.isEmpty ? nil : words
    }

    /// The file's first bytes, enough for its first line.
    private static func head(of url: URL) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 512)) ?? Data()
    }

    /// How `file` is started with `arguments`: what `CreateProcessW` is given. `environment` (nil: the input method's) is
    /// the program's, whose PATH is looked in first for an interpreter. Throws when the file isn't one that runs, its
    /// interpreter isn't installed, or an argument can't be passed (`WindowsCommandLine`).
    public static func invocation(of file: URL, arguments: [String], environment: [String: String]?) throws -> Invocation {
        guard let kind = kind(of: file) else { throw WindowsLaunchError.notRunnable(file.path) }
        let path = windowsPath(file)
        switch kind {
        case .program:
            return try standard([path] + arguments)
        case .batch:
            return Invocation(application: systemProgram("cmd.exe"), commandLine: try WindowsCommandLine.batch(script: path, arguments: arguments))
        case .powerShell:
            return try standard(try powerShell(path, file: file, core: false, environment: environment) + arguments)
        case .python:
            return try standard(try python(file, words: [], environment: environment) + arguments)
        case .windowsScript:
            // cscript takes a "//" word anywhere on its line for its own option, in quotes and after the script too
            // ("//E:jscript" runs it as another language, "//T:1" stops it, "//X" debugs it): none is the script's.
            guard !arguments.contains(where: { $0.hasPrefix("//") }) else {
                throw WindowsLaunchError.invalidArgument("an argument starting with // to a Windows Script Host script (cscript's own options)")
            }
            return try standard([systemProgram("cscript.exe"), "//NoLogo", path] + arguments)
        case .shell:
            return try standard(try bash(file, words: [], environment: environment) + arguments)
        case let .shebang(words):
            return try standard(try interpreted(file, words: words, environment: environment) + arguments)
        }
    }

    /// A program and its arguments, the command line quoted as Windows' C runtime reads it back.
    private static func standard(_ argv: [String]) throws -> Invocation {
        Invocation(application: argv[0], commandLine: try WindowsCommandLine.make(argv))
    }

    /// The interpreter a "#!" line names, its options, and the script: "#!/bin/sh" and "#!/usr/bin/env bash" with Git
    /// Bash, "#!/usr/bin/env python3" with the Python launcher (which reads the line itself), "#!/usr/bin/env pwsh" with
    /// PowerShell (a .ps1 only: PowerShell runs no other file), any other program found on the PATH or among Git's tools
    /// ("node", "perl"); a .sh whose program isn't found with Git Bash.
    private static func interpreted(_ file: URL, words: [String], environment: [String: String]?) throws -> [String] {
        var words = words
        var name = programName(words[0])
        if name == "env" {
            words.removeFirst()
            while let first = words.first, first.hasPrefix("-") || first.contains("=") { words.removeFirst() }  // -S, VAR=value
            guard let first = words.first else { throw WindowsLaunchError.notRunnable(file.path) }
            name = programName(first)
        }
        let options = Array(words.dropFirst())
        switch name {
        case "sh", "bash", "dash", "ksh":
            return try bash(file, words: options, environment: environment)
        case _ where name.hasPrefix("python"):
            return try python(file, words: options, environment: environment)
        case "pwsh", "powershell":
            guard file.pathExtension.lowercased() == "ps1" else { throw WindowsLaunchError.notRunnable(file.path) }
            return try powerShell(windowsPath(file), file: file, core: name == "pwsh", environment: environment)
        default:
            if let program = onPath(name, environment: environment) ?? gitTool(name, environment: environment) {
                return [windowsPath(program)] + options + [windowsPath(file)]
            }
            if file.pathExtension.lowercased() == "sh" { return try bash(file, words: [], environment: environment) }
            throw WindowsLaunchError.interpreterNotFound(script: file.lastPathComponent, interpreter: name)
        }
    }

    /// Git Bash, its options, and the script as bash reads paths ("C:/Users/…": `dirname "$0"` works).
    private static func bash(_ file: URL, words: [String], environment: [String: String]?) throws -> [String] {
        guard let bash = gitBash(environment) else {
            throw WindowsLaunchError.interpreterNotFound(script: file.lastPathComponent, interpreter: "Git Bash")
        }
        return [windowsPath(bash)] + words + [windowsPath(file).replacingOccurrences(of: "\\", with: "/")]
    }

    /// The Python launcher (py, which reads the script's "#!" line) and the script; else python, its options and the script.
    private static func python(_ file: URL, words: [String], environment: [String: String]?) throws -> [String] {
        let root = variable("SystemRoot", in: ProcessInfo.processInfo.environment) ?? #"C:\Windows"#
        let local = variable("LOCALAPPDATA", in: ProcessInfo.processInfo.environment)
        let launchers = [URL(fileURLWithPath: root).appendingPathComponent("py.exe")]
            + (local.map { [URL(fileURLWithPath: $0).appendingPathComponent("Programs/Python/Launcher/py.exe")] } ?? [])
        if let py = onPath("py", environment: environment) ?? launchers.first(where: { kind(of: $0) == .program }) {
            return [windowsPath(py), windowsPath(file)]
        }
        guard let python = onPath("python", environment: environment) ?? onPath("python3", environment: environment) else {
            throw WindowsLaunchError.interpreterNotFound(script: file.lastPathComponent, interpreter: "Python")
        }
        return [windowsPath(python)] + words + [windowsPath(file)]
    }

    /// Windows PowerShell (or PowerShell 7, pwsh, when the "#!" line asks for it and it is installed), without the
    /// user's profile or prompts, running the script whatever the execution policy: the user chose to run it.
    private static func powerShell(_ path: String, file: URL, core: Bool, environment: [String: String]?) throws -> [String] {
        let pwsh = core ? onPath("pwsh", environment: environment).map(windowsPath) : nil
        let shell = pwsh ?? systemProgram(#"WindowsPowerShell\v1.0\powershell.exe"#)
        return [shell, "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", path]
    }

    /// Git for Windows' bin\bash.exe, which puts Git's own tools (/usr/bin) on the PATH: found from git.exe on the PATH
    /// (in <Git>\cmd, <Git>\bin or <Git>\mingw64\bin), else where its installer puts it; else a bash.exe on the PATH
    /// that isn't WSL's (System32's, or the Store's alias for it). Nil when there is none.
    static func gitBash(_ environment: [String: String]?) -> URL? {
        if let root = gitRoot(environment) { return root.appendingPathComponent("bin/bash.exe") }
        let system = URL(fileURLWithPath: systemProgram(""), isDirectory: true).standardizedFileURL.path.lowercased()
        for path in searchPaths(environment) {
            for folder in folders(inPath: path) {
                let place = URL(fileURLWithPath: folder, isDirectory: true).standardizedFileURL
                let bash = place.appendingPathComponent("bash.exe")
                let lowercased = place.path.lowercased()
                guard !lowercased.hasPrefix(system), !lowercased.contains("/microsoft/windowsapps"), kind(of: bash) == .program else { continue }
                return bash
            }
        }
        return nil
    }

    /// Git for Windows' folder: the one with bin\bash.exe, one or two folders above git.exe on the PATH (its <Git>\cmd,
    /// <Git>\bin or <Git>\mingw64\bin), or where the installer puts it. No higher: a git.exe elsewhere (a package
    /// manager's shim, a tool's own copy) doesn't make a bin\bash.exe further up Git Bash.
    static func gitRoot(_ environment: [String: String]?) -> URL? {
        var roots: [URL] = []
        for path in searchPaths(environment) {
            guard let git = folders(inPath: path).lazy
                .map({ URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("git.exe") })
                .first(where: { kind(of: $0) == .program }) else { continue }
            var folder = git.deletingLastPathComponent()
            for _ in 0..<2 {
                folder = folder.deletingLastPathComponent()
                roots.append(folder)
            }
        }
        let own = ProcessInfo.processInfo.environment
        for variable in ["ProgramW6432", "ProgramFiles", "ProgramFiles(x86)"] {
            if let folder = Self.variable(variable, in: own) { roots.append(URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent("Git")) }
        }
        if let local = variable("LOCALAPPDATA", in: own) {
            roots.append(URL(fileURLWithPath: local, isDirectory: true).appendingPathComponent("Programs/Git"))
        }
        return roots.first { kind(of: $0.appendingPathComponent("bin/bash.exe")) == .program }
    }

    /// One of Git's tools (its /usr/bin: perl, awk, …), for a "#!" line that names one.
    private static func gitTool(_ name: String, environment: [String: String]?) -> URL? {
        guard let root = gitRoot(environment) else { return nil }
        let tool = root.appendingPathComponent("usr/bin/\(name).exe")
        return kind(of: tool) == .program ? tool : nil
    }

    /// The program (.exe, .com) `name` names, on the program's PATH, then on the input method's. (Not a batch file: an
    /// interpreter's arguments are the script's, which cmd.exe would read.)
    private static func onPath(_ name: String, environment: [String: String]?) -> URL? {
        for path in searchPaths(environment) {
            if let found = find(name, path: path), kind(of: found) == .program { return found }
        }
        return nil
    }

    /// The PATHs an interpreter is looked for in: the program's, then the input method's.
    private static func searchPaths(_ environment: [String: String]?) -> [String] {
        let own = variable("PATH", in: ProcessInfo.processInfo.environment)
        return [environment.flatMap { variable("PATH", in: $0) }, own].compactMap { $0 }
    }

    /// The name a program goes by: "bash" for "/bin/bash", "python3" for "C:\Python\python3.exe".
    private static func programName(_ word: String) -> String {
        var name = String(word.split(whereSeparator: CorePaths.isSeparator).last ?? Substring(word)).lowercased()
        if name.hasSuffix(".exe") { name.removeLast(4) }
        return name
    }

    /// A file in Windows' System32 folder ("C:\Windows\System32\cmd.exe").
    static func systemProgram(_ name: String) -> String {
        var buffer = [WCHAR](repeating: 0, count: Int(MAX_PATH) + 1)
        let count = Int(GetSystemDirectoryW(&buffer, DWORD(buffer.count)))
        let folder = count > 0 && count < buffer.count
            ? String(decoding: buffer[..<count], as: UTF16.self)
            : (variable("SystemRoot", in: ProcessInfo.processInfo.environment) ?? #"C:\Windows"#) + #"\System32"#
        return name.isEmpty ? folder : folder + #"\"# + name
    }

    /// `url`'s path as Windows writes it ("C:\Users\…").
    static func windowsPath(_ url: URL) -> String {
        url.withUnsafeFileSystemRepresentation { String(cString: $0!) }
    }
}

/// Why a program couldn't be started on Windows.
public enum WindowsLaunchError: Error, LocalizedError, Equatable {
    /// Neither a program Windows starts nor a script of a kind it is known how to run.
    case notRunnable(String)
    /// The interpreter the script needs isn't installed ("Git Bash", "Python", or what its "#!" line names).
    case interpreterNotFound(script: String, interpreter: String)
    /// An argument or a variable that can't be passed: one with a NUL character, a line break in one for a batch
    /// file (cmd.exe would cut the command there: `WindowsCommandLine.batch`), or one starting with "//" for a Windows
    /// Script Host script (cscript's options).
    case invalidArgument(String)
    /// A Windows call failed: its name and the error it gave.
    case system(String, UInt32)

    public var errorDescription: String? {
        switch self {
        case let .notRunnable(path): return "\((path as NSString).lastPathComponent) isn't a program or a script Windows can run"
        case let .interpreterNotFound(script, interpreter): return "\(script) needs \(interpreter), which isn't installed"
        case let .invalidArgument(reason): return "Can't start the program: \(reason)"
        case let .system(call, code): return "Can't start the program (\(call): error \(code))"
        }
    }
}
#endif
