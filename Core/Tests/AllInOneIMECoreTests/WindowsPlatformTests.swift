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
        #expect(WindowsPrograms.folders(inPath: #"C:\a;;"C:\b c";C:/d:/e"#) == [#"C:\a"#, #"C:\b c"#, "C:/d", "/e"])
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
}
#endif
