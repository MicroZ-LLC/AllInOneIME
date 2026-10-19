#if os(Windows)
import Foundation
import Testing
import WinSDK
@testable import AllInOneIMECore

/// The Windows implementations behind `Platform` (Platform/Windows/): the launcher (`WindowsProcessLauncher`, how it finds
/// and quotes programs), the Credential Manager store and the Recycle Bin.
struct WindowsPlatformTests {
    /// A folder of its own, removed after.
    final class Folder {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("windows-platform-\(UUID().uuidString)", isDirectory: true)
        init() throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        deinit { try? FileManager.default.removeItem(at: url) }

        @discardableResult
        func file(_ name: String, _ text: String) throws -> URL {
            let file = url.appendingPathComponent(name)
            try Data(text.utf8).write(to: file)
            return file
        }
    }

    /// Runs `file` with `arguments` through the launcher: what it printed, and its exit status.
    func run(_ file: URL, _ arguments: [String] = [], environment: [String: String]? = nil, directory: URL? = nil) throws -> (String, Int32) {
        let output = Pipe()
        let process = try WindowsProcessLauncher().launch(LaunchSpec(executable: file, arguments: arguments, environment: environment,
                                                                     directory: directory, standardInput: .null,
                                                                     standardOutput: .pipe(output), standardError: .pipe(output)))
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n"), process.terminationStatus)
    }

    // MARK: Command lines

    /// What the C runtime (`CommandLineToArgvW`, its rules) reads back from the line written is what was given.
    @Test func commandLinesReadBackAsGiven() throws {
        let arguments = ["", "plain", "a b", "tab\there", #"a"b"#, #"a\"#, #"a\\"#, #"a\\"b"#, #"\""#, #"""#, #""""#, #"C:\Program Files\"#,
                         #"\\server\share\"#, "中文 空格", "trailing\\ \\", "%PATH%", "a&b|c<d>e^f"]
        let line = try WindowsCommandLine.make([#"C:\Program Files\tool.exe"#] + arguments)
        var count: Int32 = 0
        let parsed = line.withCString(encodedAs: UTF16.self) { CommandLineToArgvW($0, &count) }
        defer { LocalFree(parsed) }
        let read = (0..<Int(count)).map { String(decodingCString: parsed![$0]!, as: UTF16.self) }
        #expect(read == [#"C:\Program Files\tool.exe"#] + arguments)
        #expect(throws: WindowsLaunchError.self) { try WindowsCommandLine.make(["tool.exe", "a\0b"]) }
    }

    /// A batch file's arguments reach it as text: cmd.exe runs nothing in them and expands no variable (BatBadBut).
    @Test func batchFilesRunNothingInTheirArguments() throws {
        let folder = try Folder()
        let script = try folder.file("args.bat", "@echo off\r\necho(%1\r\necho(%2\r\necho(%3\r\necho(%4\r\n")
        let (output, status) = try run(script, ["a&echo INJECTED", "%PATH%", "x|y>z", #"say "hi""#])
        let lines = output.split(separator: "\n").map(String.init)
        #expect(status == 0)
        #expect(lines == [#""a&echo INJECTED""#, #""%PATH%""#, #""x|y>z""#, #""say ""hi""""#], "\(output)")
        #expect(throws: WindowsLaunchError.self) { try run(script, ["one\ntwo"]) }
    }

    /// The environment and working directory given are the program's (SystemRoot added when the caller's has none).
    @Test func environmentAndDirectory() throws {
        let folder = try Folder()
        let script = try folder.file("where.bat", "@echo off\r\ncd\r\necho %ALLINONEIME_TEST%\r\necho %SystemRoot%\r\n")
        let (output, _) = try run(script, environment: ["ALLINONEIME_TEST": "given"], directory: folder.url)
        let lines = output.split(separator: "\n").map(String.init)
        #expect(lines.count == 3 && lines[1] == "given" && !lines[2].hasPrefix("%"), "\(output)")
        #expect(lines.first.map { URL(fileURLWithPath: $0).standardizedFileURL.path } == folder.url.standardizedFileURL.path)
    }

    // MARK: Finding programs

    /// PATH split on ";", PATHEXT's extensions added, a script by its extension; never the current folder.
    @Test func programsAreFoundAsWindowsFindsThem() throws {
        let folder = try Folder()
        let batch = try folder.file("planted.bat", "@echo planted\r\n")
        let script = try folder.file("tool.ps1", "Write-Output tool\r\n")
        try folder.file("notes.txt", "text")
        let path = #"C:\nowhere;"# + "\"" + WindowsPrograms.windowsPath(folder.url) + "\""
        #expect(WindowsPrograms.find("planted", path: path)?.standardizedFileURL == batch.standardizedFileURL)
        #expect(WindowsPrograms.find("PLANTED.BAT", path: path) != nil)
        #expect(WindowsPrograms.find("tool.ps1", path: path)?.standardizedFileURL == script.standardizedFileURL)
        #expect(WindowsPrograms.find("tool", path: path) == nil, "PATHEXT has no .ps1")
        #expect(WindowsPrograms.find("notes.txt", path: path) == nil)
        #expect(WindowsPrograms.find("planted", path: nil) == nil)
        #expect(WindowsPrograms.find(WindowsPrograms.windowsPath(batch), path: nil) != nil)
        #expect(WindowsPrograms.find(#".\planted.bat"#, path: nil, directory: folder.url) != nil)
        #expect(WindowsPrograms.folders(inPath: #"C:\a;;"C:\b c";C:/d:C:/e"#) == [#"C:\a"#, #"C:\b c"#, "C:/d", "C:/e"])
    }

    /// Only PATH's folders written in full are looked in: not ".", "bin", "C:bin", "\bin" or "/usr/bin", which are
    /// wherever the input method runs, on whichever drive.
    @Test func onlyFullyQualifiedPathFolders() throws {
        #expect(WindowsPrograms.folders(inPath: #".;bin;..\bin;C:bin;C:;\bin;/usr/bin;C:\a;C:/b;\\server\share\c;\\?\C:\d;"C:\e f";C:/g:/h"#)
                == [#"C:\a"#, "C:/b", #"\\server\share\c"#, #"\\?\C:\d"#, #"C:\e f"#, "C:/g"])
        let folder = try Folder()
        let bin = folder.url.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data("@echo planted\r\n".utf8).write(to: bin.appendingPathComponent("planted.bat"))
        let full = WindowsPrograms.windowsPath(bin)
        #expect(WindowsPrograms.find("planted", path: full) != nil)
        // The same folder from the current drive's root ("\Users\…"): not taken.
        let rooted = String(full.dropFirst(2))
        #expect(WindowsPrograms.find("planted", path: rooted) == nil)
        #expect(WindowsPrograms.find("planted", path: rooted.replacingOccurrences(of: "\\", with: "/")) == nil)
    }

    /// A device's name is no program in any folder ("NUL", "con.bat"); a batch file whose path has a "%" isn't run
    /// (cmd.exe would expand it there).
    @Test func devicesAndPercentPathsAreRefused() throws {
        let folder = try Folder()
        for name in ["NUL", "nul.exe", "CON.bat", "com1.cmd", "Aux.ps1", "conin$"] {
            #expect(WindowsPrograms.kind(of: folder.url.appendingPathComponent(name)) == nil, "\(name)")
        }
        #expect(WindowsPrograms.find("con", path: WindowsPrograms.windowsPath(folder.url)) == nil)
        let sub = folder.url.appendingPathComponent("100%PATH%", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let script = sub.appendingPathComponent("x.bat")
        try Data("@echo x\r\n".utf8).write(to: script)
        #expect(throws: WindowsLaunchError.self) { try run(script) }
        #expect(throws: WindowsLaunchError.self) { try WindowsCommandLine.batch(script: #"C:\Users\me\%TEMP%\x.bat"#, arguments: []) }
    }

    /// Git Bash is found one or two folders above git.exe on the PATH (Git's cmd, bin, mingw64\bin), no higher.
    @Test func gitBashIsLookedForNearGitOnly() throws {
        let folder = try Folder()
        for name in ["Git/bin/bash.exe", "Git/mingw64/bin/git.exe", "Git/cmd/git.exe", "Git/a/b/c/git.exe"] {
            let file = folder.url.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("MZ".utf8).write(to: file)
        }
        let bash = folder.url.appendingPathComponent("Git/bin/bash.exe").standardizedFileURL.path
        func found(_ git: String) -> String? {
            let path = WindowsPrograms.windowsPath(folder.url.appendingPathComponent(git, isDirectory: true))
            return WindowsPrograms.gitBash(["PATH": path])?.standardizedFileURL.path
        }
        #expect(found("Git/cmd") == bash)
        #expect(found("Git/mingw64/bin") == bash)
        #expect(found("Git/a/b/c") != bash, "three folders up")
    }

    /// .ps1 runs with PowerShell, .py with Python, .sh and "#!/bin/sh" with Git Bash: each gets its arguments as given.
    @Test func scriptsRunThroughTheirInterpreters() throws {
        let folder = try Folder()
        let arguments = ["a b", #"say "hi""#, ""]
        let ps1 = try folder.file("args.ps1", "Write-Output ($args -join '|')\r\n")
        #expect(try run(ps1, arguments).0.trimmingCharacters(in: .newlines) == #"a b|say "hi"|"#)
        if (try? WindowsPrograms.invocation(of: folder.file("probe.py", ""), arguments: [], environment: nil)) != nil {
            let py = try folder.file("args.py", "import sys\nprint('|'.join(sys.argv[1:]))\n")
            #expect(try run(py, arguments).0.trimmingCharacters(in: .newlines) == #"a b|say "hi"|"#)
        }
        if WindowsPrograms.gitBash(nil) != nil {
            let sh = try folder.file("args.sh", "printf '%s|' \"$@\"\n")
            let shebang = try folder.file("args", "#!/bin/sh\nprintf '%s|' \"$@\"\n")
            #expect(try run(sh, arguments).0 == #"a b|say "hi"||"#)
            #expect(try run(shebang, arguments).0 == #"a b|say "hi"||"#)
        }
        #expect(throws: WindowsLaunchError.self) { try run(folder.file("notes.txt", "text")) }
    }

    /// Every argument in quotes: Git Bash's bash (MSYS2's runtime, like Cygwin's) expands none of `*`, `~`, `@file`
    /// and `'` in a word that isn't, as a shell would.
    @Test(.enabled(if: WindowsPrograms.gitBash(nil) != nil, "no Git Bash"))
    func msysProgramsGetTheirArgumentsAsGiven() throws {
        let folder = try Folder()
        try folder.file("x", "read from the file\n")  // what `@x` would be replaced with
        try folder.file("other.txt", "")  // what `*` would match
        let sh = try folder.file("args.sh", "printf '%s|' \"$@\"\n")
        let arguments = ["*", "~", "it's", "@x", "*.txt", "~/x", "o?her.txt", "[o]ther.txt", "{a,b}", "'quoted'", #"a\b"#]
        let (output, status) = try run(sh, arguments, directory: folder.url)
        #expect(status == 0)
        #expect(output == arguments.map { $0 + "|" }.joined())
        let line = try WindowsCommandLine.make(["tool.exe", "plain", "*"])
        #expect(line == #""tool.exe" "plain" "*""#)
    }

    /// A Windows Script Host script gets its arguments, but none starting with "//": cscript would take it for its own
    /// option, in quotes and after the script too ("//E:jscript" runs it as JScript).
    @Test func windowsScriptsGetNoHostOptions() throws {
        let folder = try Folder()
        let vbs = try folder.file("args.vbs", "For Each a In WScript.Arguments\r\nWScript.Echo \"[\" & a & \"]\"\r\nNext\r\n")
        let (output, status) = try run(vbs, ["a b", "x//y", "/c", "*"])
        #expect(status == 0)
        #expect(output == "[a b]\n[x//y]\n[/c]\n[*]\n")
        #expect(throws: WindowsLaunchError.self) { try run(vbs, ["//E:jscript"]) }
        #expect(throws: WindowsLaunchError.self) { try run(vbs, ["a", "//T:1"]) }
    }

    // MARK: Extensions

    /// A batch file (.bat, .cmd) is an extension's script like a .sh or a .ps1: its bundle loads it, and it runs with its
    /// arguments through cmd.exe's escaping (`WindowsCommandLine.batch`).
    @Test func batchFileExtensionsLoadAndRun() async throws {
        let folder = ScriptFolder()
        folder.add("t/extension.json", #"""
            {"schemaVersion": 1, "name": "t",
             "commands": [{"script": "hello.bat", "name": "hello"}, {"script": "other.CMD", "name": "other"}]}
            """#)
        folder.add("t/hello.bat", "@echo off\r\necho(%1\r\n")
        folder.add("t/other.CMD", "@echo other\r\n")
        let index = folder.load()
        #expect(index.skipped.isEmpty, "\(index.skipped)")
        #expect(index.commands.map(\.name) == ["hello", "other"])
        let hello = try #require(index.commands.first { $0.name == "hello" })
        var text = ""
        for try await update in CommandRunner.run(hello, arguments: ["it's & 100%"]) where update.isFinal { text = update.text }
        #expect(text.trimmingCharacters(in: .whitespacesAndNewlines) == #""it's & 100%""#)
        // By its extension, whatever Foundation's isExecutableFile says of it.
        for name in ["hello.bat", "other.CMD"] {
            let file = folder.url.appendingPathComponent("t/\(name)")
            #expect(ScriptCommand.launch(for: file, firstLine: "@echo off", executable: false) == [file.path])
        }
    }

    // MARK: Stopping

    /// `terminate` ends what the program started too: a batch file's child, which would write a file 2 s later, doesn't.
    @Test func stoppingEndsTheWholeTree() async throws {
        let folder = try Folder()
        try folder.file("late.bat", "@ping -n 3 127.0.0.1 >nul\r\n@echo late>\"%~dp0marker\"\r\n")
        let tree = try folder.file("tree.bat", "@start \"\" /b \"%~dp0late.bat\"\r\n@ping -n 30 127.0.0.1 >nul\r\n")
        let marker = folder.url.appendingPathComponent("marker")

        // Left alone, the child writes it.
        let alone = try WindowsProcessLauncher().launch(LaunchSpec(executable: tree, standardInput: .null, standardOutput: .null, standardError: .null))
        let deadline = Date().addingTimeInterval(15)
        while !FileManager.default.fileExists(atPath: marker.path), Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        #expect(FileManager.default.fileExists(atPath: marker.path), "the child never wrote it: the test proves nothing")
        #expect(alone.kill())
        try await Self.ended(alone)
        try FileManager.default.removeItem(at: marker)

        // Stopped, it never does.
        let stopped = try WindowsProcessLauncher().launch(LaunchSpec(executable: tree, standardInput: .null, standardOutput: .null, standardError: .null))
        try await Task.sleep(for: .milliseconds(500))
        #expect(stopped.treeIsRunning)
        #expect(stopped.terminate())
        try await Self.ended(stopped)
        #expect(!stopped.treeIsRunning && !stopped.isRunning)
        try await Task.sleep(for: .seconds(3))
        #expect(!FileManager.default.fileExists(atPath: marker.path), "the child outlived the stop")
        #expect(!stopped.terminate() && !stopped.kill(), "nothing left to stop")
    }

    /// Waits (without holding a thread) until `process` and what it started have ended, 5 s at most.
    static func ended(_ process: any LaunchedProcess) async throws {
        let deadline = Date().addingTimeInterval(5)
        while process.treeIsRunning || process.isRunning, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    }

    /// `onExit` is called once it has ended, with its status.
    @Test func endingIsReported() async throws {
        let folder = try Folder()
        let script = try folder.file("exit.bat", "@exit /b 7\r\n")
        let status = await withCheckedContinuation { continuation in
            do {
                _ = try WindowsProcessLauncher().launch(LaunchSpec(executable: script, standardInput: .null, standardOutput: .null,
                                                                   standardError: .null) { continuation.resume(returning: $0.terminationStatus) })
            } catch {
                continuation.resume(returning: -1)
            }
        }
        #expect(status == 7)
    }

    // MARK: Credential Manager

    /// Whether this logon has a Credential Manager to write to: an SSH login with a key has none (error 1312,
    /// ERROR_NO_SUCH_LOGON_SESSION), a desktop one does.
    static let hasCredentialManager: Bool = {
        let store = APIKeys.Keychain.credentialManager(service: "AllInOneIME tests probe \(UUID().uuidString)",
                                                       folder: FileManager.default.temporaryDirectory)
        guard store.write("probe", "probe", "", "", nil) == .ok else { return false }
        _ = store.delete("probe")
        return true
    }()

    /// Keys kept in the Credential Manager under a service of the test's own; a long one in a DPAPI-protected file.
    @Test(.enabled(if: hasCredentialManager, "no Credential Manager in this logon session (an SSH login with a key)"))
    func credentialManagerKeepsKeys() throws {
        let folder = try Folder()
        let service = "AllInOneIME tests \(UUID().uuidString)"
        let store = APIKeys.Keychain.credentialManager(service: service, folder: folder.url.appendingPathComponent("Secrets"))
        let account = "provider"
        defer { _ = store.delete(account) }

        #expect(store.attributes(account) == nil && store.read(account) == nil)
        #expect(store.write(account, "sk-short-key-1234", "AllInOneIME: Test", "api.example.com", "1234") == .ok)
        #expect(store.read(account) == "sk-short-key-1234")
        let first = try #require(store.attributes(account))
        #expect(first.comment == "api.example.com" && first.ending == "1234" && first.created != nil && first.modified != nil)

        #expect(store.setComment(account, "other.example.com") == .ok)
        let second = try #require(store.attributes(account))
        #expect(second.comment == "other.example.com" && second.created == first.created && second.ending == "1234")
        #expect(store.read(account) == "sk-short-key-1234")

        // Longer than a credential holds: in a file of its own, encrypted.
        let long = "sk-" + String(repeating: "abcdefghij", count: 400)
        #expect(store.write(account, long, "AllInOneIME: Test", "api.example.com", "ghij") == .ok)
        #expect(store.read(account) == long)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.url.appendingPathComponent("Secrets").path)
        #expect(files.count == 1 && files[0].hasSuffix(".secret"))
        let sealed = try Data(contentsOf: folder.url.appendingPathComponent("Secrets/\(files[0])"))
        #expect(sealed.range(of: Data("abcdefghij".utf8)) == nil, "the key is in the file as it is")
        #expect(store.attributes(account)?.created == first.created)

        // Short again: the file goes.
        #expect(store.write(account, "sk-short-key-5678", "AllInOneIME: Test", "", "5678") == .ok)
        #expect(store.read(account) == "sk-short-key-5678")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.appendingPathComponent("Secrets").path).isEmpty)

        #expect(store.delete(account) == .ok)
        #expect(store.delete(account) == .notFound && store.setComment(account, "x") == .notFound)
        #expect(store.attributes(account) == nil && store.read(account) == nil)
        #expect(store.message(Int32(ERROR_NOT_FOUND))?.isEmpty == false)
    }

    // MARK: Recycle Bin

    /// What the core trashes leaves its folder for the Recycle Bin; nothing there is an error.
    @Test func trashMovesToTheRecycleBin() throws {
        let folder = try Folder()
        let file = try folder.file("AllInOneIME-trash-test-\(UUID().uuidString).txt", "x")
        let sub = folder.url.appendingPathComponent("AllInOneIME-trash-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        try Data("y".utf8).write(to: sub.appendingPathComponent("inside.txt"))
        try SystemFileOps().trash(file)
        try SystemFileOps().trash(sub)
        #expect(!FileManager.default.fileExists(atPath: file.path) && !FileManager.default.fileExists(atPath: sub.path))
        #expect(throws: (any Error).self) { try SystemFileOps().trash(file) }
    }

    /// What is on a drive the Recycle Bin doesn't keep (a share, a removable drive) is refused and left there: the
    /// Recycle Bin would delete it for good. Here the test's own file through the drive's administrative share
    /// (\\localhost\C$), when that can be reached.
    @Test func trashRefusesWhatTheRecycleBinWouldDelete() throws {
        let folder = try Folder()
        let file = try folder.file("AllInOneIME-trash-test-\(UUID().uuidString).txt", "x")
        let local = WindowsPrograms.windowsPath(file)
        guard local.dropFirst().hasPrefix(#":\"#) else { return }
        let shared = URL(fileURLWithPath: #"\\localhost\"# + local.prefix(1) + "$" + local.dropFirst(2))
        guard FileManager.default.fileExists(atPath: shared.path) else { return }  // no administrative share for this user
        #expect { try SystemFileOps().trash(shared) } throws: { ($0 as? CocoaError)?.code == .featureUnsupported }
        #expect(FileManager.default.fileExists(atPath: file.path), "deleted, not trashed")
    }
}
#endif
