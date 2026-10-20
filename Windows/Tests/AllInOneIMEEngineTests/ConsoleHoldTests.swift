#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import Foundation
import Testing
import WinSDK

/// Another process's console, through Python (`AttachConsole` in a process of its own: the test runner's console, if it
/// has one, is left alone): what its screen says, and a key typed into it (`WriteConsoleInputW`, into that console only).
struct ConsoleProbe {
    let python: URL
    let script: URL

    init(folder: URL) throws {
        python = try StubProvider.python()
        script = folder.appendingPathComponent("console-probe.py")
        try Data("""
            import ctypes, json, sys
            from ctypes import wintypes as w
            k = ctypes.WinDLL("kernel32", use_last_error=True)
            k.CreateFileW.restype = w.HANDLE
            k.CreateFileW.argtypes = [w.LPCWSTR, w.DWORD, w.DWORD, w.LPVOID, w.DWORD, w.DWORD, w.HANDLE]
            class COORD(ctypes.Structure): _fields_ = [("X", w.SHORT), ("Y", w.SHORT)]
            class SMALL_RECT(ctypes.Structure):
                _fields_ = [("Left", w.SHORT), ("Top", w.SHORT), ("Right", w.SHORT), ("Bottom", w.SHORT)]
            class INFO(ctypes.Structure):
                _fields_ = [("size", COORD), ("cursor", COORD), ("attributes", w.WORD), ("window", SMALL_RECT),
                            ("largest", COORD)]
            class KEY(ctypes.Structure):
                _fields_ = [("down", w.BOOL), ("repeat", w.WORD), ("vk", w.WORD), ("scan", w.WORD), ("char", w.WCHAR),
                            ("state", w.DWORD)]
            class RECORD(ctypes.Structure): _fields_ = [("type", w.WORD), ("key", KEY)]
            pid, action = int(sys.argv[1]), sys.argv[2]
            k.FreeConsole()
            if not k.AttachConsole(pid):
                print(json.dumps({"error": ctypes.get_last_error()}), flush=True)
                sys.exit(1)
            if action == "read":
                out = k.CreateFileW("CONOUT$", 0xC0000000, 3, None, 3, 0, None)
                info = INFO()
                k.GetConsoleScreenBufferInfo(w.HANDLE(out), ctypes.byref(info))
                lines = []
                for y in range(info.cursor.Y + 1):
                    buffer = ctypes.create_unicode_buffer(info.size.X + 1)
                    read = w.DWORD()
                    k.ReadConsoleOutputCharacterW(w.HANDLE(out), buffer, info.size.X, COORD(0, y), ctypes.byref(read))
                    lines.append(buffer.value[:read.value].rstrip())
                print(json.dumps({"lines": lines}), flush=True)
            else:
                into = k.CreateFileW("CONIN$", 0xC0000000, 3, None, 3, 0, None)
                records = (RECORD * 2)(RECORD(1, KEY(1, 1, 0x58, 0x2D, "x", 0)), RECORD(1, KEY(0, 1, 0x58, 0x2D, "x", 0)))
                written = w.DWORD()
                print(json.dumps({"written": k.WriteConsoleInputW(w.HANDLE(into), records, 2, ctypes.byref(written))}),
                      flush=True)

            """.utf8).write(to: script)
    }

    /// `python console-probe.py <pid> <action>`'s JSON.
    func run(_ pid: DWORD, _ action: String) -> [String: Any] {
        let process = Process()
        process.executableURL = python
        process.arguments = ["-I", script.path, String(pid), action]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [:] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// The console's screen, its lines up to the cursor's, joined.
    func screen(_ pid: DWORD) -> String {
        ((run(pid, "read")["lines"] as? [String]) ?? []).joined(separator: "\n")
    }

    /// A key typed into the console (x, down and up).
    func pressKey(_ pid: DWORD) -> Bool { (run(pid, "key")["written"] as? Int ?? 0) != 0 }
}

extension OnTheDesktop {
    /// A console window the engine opens stays open once its program has ended (`ConsoleHold`), as the Mac's Terminal
    /// keeps its window: the program's output and its exit code stay on the screen until a key is pressed.
    @Suite(.serialized)
    struct ConsoleHoldTests {
        /// A batch file that prints what it is given and ends with exit code 3, started as a `terminal` command is, with
        /// a prompt that goes in a file (its line break: cmd.exe would end the command there). Its console's process is
        /// still there after it, the output and "exited with code 3" on its screen, the prompt's file gone; a key closes
        /// it.
        @Test(.timeLimit(.minutes(1))) func aConsoleStaysOpenAfterItsProgramEnds() throws {
            try #require(FileManager.default.fileExists(atPath: debugEngine.path), "build the engine first (swift build)")
            let folder = try temporaryFolder("hold")
            defer { try? FileManager.default.removeItem(at: folder) }
            let prompts = folder.appendingPathComponent("prompts", isDirectory: true)
            try Data("@echo held output %*\r\n@exit /b 3\r\n".utf8).write(to: folder.appendingPathComponent("hold.cmd"))
            let probe = try ConsoleProbe(folder: folder)

            let path = folder.withUnsafeFileSystemRepresentation { String(cString: $0!) }
            let pid = try testShellThread.syncThrowing {
                try testWindowsSystem().startInConsole(["hold", "--"], prompt: "line one\nline two", path: path, promptFolder: prompts)
            }
            let process = try #require(OpenProcess(DWORD(SYNCHRONIZE) | DWORD(PROCESS_TERMINATE), false, pid))
            defer {
                TerminateProcess(process, 0)
                CloseHandle(process)
            }
            let ended = ConsoleHold.endMessage("hold", code: 3)
            let deadline = Date().addingTimeInterval(20)
            var screen = ""
            while !screen.contains(ended), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
                screen = probe.screen(pid)
            }
            #expect(screen.contains(#"held output -- "The request is in the file "#), "\(screen)")
            #expect(screen.contains(ended), "\(screen)")
            // The program has ended, its console hasn't: it waits for a key.
            #expect(WaitForSingleObject(process, 500) == WAIT_TIMEOUT)
            // The prompt's file went with the program.
            #expect(((try? FileManager.default.contentsOfDirectory(atPath: prompts.path)) ?? []).isEmpty)
            #expect(probe.pressKey(pid))
            #expect(WaitForSingleObject(process, 5000) == WAIT_OBJECT_0)
        }

        /// The four variables a console's process reads are this launch's only: one the engine has in its own
        /// environment (inherited from the app that started it) never goes on, so a console without a prompt's file
        /// can't delete a file it names.
        @Test func onlyThisLaunchsVariablesGoToTheConsole() throws {
            func set(_ name: String, _ value: String?) {
                _ = name.withCString(encodedAs: UTF16.self) { name in
                    if let value { _ = value.withCString(encodedAs: UTF16.self) { SetEnvironmentVariableW(name, $0) } }
                    else { _ = SetEnvironmentVariableW(name, nil) }
                }
            }
            for name in ConsoleHold.variables { set(name, #"C:\elsewhere\agent-prompt-stale.txt"#) }
            defer { for name in ConsoleHold.variables { set(name, nil) } }
            func entries(_ command: ConsoleCommand) -> [String] {
                String(decoding: ConsoleHold.environment(for: command, title: "git"), as: UTF16.self).split(separator: "\0").map(String.init)
            }
            let plain = entries(ConsoleCommand(application: #"C:\Tools\git.exe"#, commandLine: #""C:\Tools\git.exe" status"#))
            #expect(!plain.contains { $0.uppercased().hasPrefix(ConsoleHold.promptFileVariable + "=") })
            #expect(plain.contains("\(ConsoleHold.applicationVariable)=C:\\Tools\\git.exe") && plain.contains("\(ConsoleHold.titleVariable)=git"))
            #expect(plain.filter { $0.uppercased().hasPrefix(ConsoleHold.commandLineVariable + "=") }.count == 1)
            let file = URL(fileURLWithPath: #"C:\Temp\AllInOneIME\agent-prompt-1.txt"#)
            let withFile = entries(ConsoleCommand(application: #"C:\Tools\agent.exe"#, commandLine: "agent", promptFile: file))
            #expect(withFile.filter { $0.uppercased().hasPrefix(ConsoleHold.promptFileVariable + "=") }
                    == ["\(ConsoleHold.promptFileVariable)=\(file.withUnsafeFileSystemRepresentation { String(cString: $0!) })"])
        }

        /// The program starts at once, whatever the window that shows the console is doing: in a pseudo console that no
        /// terminal takes (its window, `GetConsoleWindow`'s, never gets an owner), as a default terminal that is slow to
        /// show it, or never says, would leave it, the console's process brings the window to the front only once the
        /// program runs (it tries for 5 s).
        @Test(.timeLimit(.minutes(1))) func theProgramDoesntWaitForTheWindow() throws {
            try #require(FileManager.default.fileExists(atPath: debugEngine.path), "build the engine first (swift build)")
            let folder = try temporaryFolder("hold-pty")
            defer { try? FileManager.default.removeItem(at: folder) }
            let marker = folder.appendingPathComponent("started.txt")
            let markerPath = marker.withUnsafeFileSystemRepresentation { String(cString: $0!) }
            var system = [WCHAR](repeating: 0, count: Int(MAX_PATH))
            let count = Int(GetSystemDirectoryW(&system, UINT(MAX_PATH)))
            let cmd = String(decoding: system.prefix(count), as: UTF16.self) + #"\cmd.exe"#
            // A pseudo console of the test's own, its output read (and dropped) so that it never blocks.
            var inputRead: HANDLE?, inputWrite: HANDLE?, outputRead: HANDLE?, outputWrite: HANDLE?
            #expect(CreatePipe(&inputRead, &inputWrite, nil, 0) && CreatePipe(&outputRead, &outputWrite, nil, 0))
            var console: HPCON?
            #expect(CreatePseudoConsole(COORD(X: 120, Y: 30), inputRead, outputWrite, 0, &console) == S_OK)
            nonisolated(unsafe) let reader = outputRead
            Thread.detachNewThread {
                var buffer = [UInt8](repeating: 0, count: 4096)
                var read: DWORD = 0
                while ReadFile(reader, &buffer, DWORD(buffer.count), &read, nil), read > 0 {}
            }
            var size: SIZE_T = 0
            InitializeProcThreadAttributeList(nil, 1, 0, &size)
            let list = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
            defer { list.deallocate() }
            let attributes: LPPROC_THREAD_ATTRIBUTE_LIST = OpaquePointer(list)
            #expect(InitializeProcThreadAttributeList(attributes, 1, 0, &size))
            defer { DeleteProcThreadAttributeList(attributes) }
            // PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: a macro Swift doesn't import.
            #expect(UpdateProcThreadAttribute(attributes, 0, DWORD_PTR(0x0002_0016), UnsafeMutableRawPointer(console),
                                              SIZE_T(MemoryLayout<HPCON>.size), nil, nil))
            var environment = ConsoleHold.environmentBlock(adding: [
                ConsoleHold.applicationVariable: cmd,
                ConsoleHold.commandLineVariable: "cmd.exe /d /c \"echo started> \"\(markerPath)\"\"",
                ConsoleHold.titleVariable: "pty",
            ])
            let holder = debugEngine.withUnsafeFileSystemRepresentation { String(cString: $0!) }
            var commandLine = Array("\"\(holder)\" \(ConsoleHold.option)".utf16) + [0]
            var startup = STARTUPINFOEXW()
            startup.StartupInfo.cb = DWORD(MemoryLayout<STARTUPINFOEXW>.size)
            startup.lpAttributeList = attributes
            var info = PROCESS_INFORMATION()
            let launched = Date()
            let ok = holder.withCString(encodedAs: UTF16.self) { application in
                environment.withUnsafeMutableBufferPointer { environment in
                    CreateProcessW(application, &commandLine, nil, nil, false,
                                   DWORD(EXTENDED_STARTUPINFO_PRESENT) | DWORD(CREATE_UNICODE_ENVIRONMENT),
                                   environment.baseAddress, nil, &startup.StartupInfo, &info)
                }
            }
            try #require(ok, "couldn't start the console's process (error \(GetLastError()))")
            defer {
                TerminateProcess(info.hProcess, 0)
                WaitForSingleObject(info.hProcess, 5000)
                CloseHandle(info.hThread)
                CloseHandle(info.hProcess)
                ClosePseudoConsole(console)
                for handle in [inputRead, inputWrite, outputWrite, outputRead] { CloseHandle(handle) }
            }
            let deadline = Date().addingTimeInterval(15)
            while !FileManager.default.fileExists(atPath: marker.path), Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            let waited = Date().timeIntervalSince(launched)
            #expect(FileManager.default.fileExists(atPath: marker.path))
            #expect(waited < 3, "the program started \(waited) s after its console's process")
        }

        /// What the console's process is given is in its environment (the whole command line a program may have, in
        /// none of its own), and gone from it before the program starts: the program's environment is the engine's.
        @Test func theProgramIsInTheConsolesEnvironmentNotItsCommandLine() throws {
            let long = String(repeating: "x", count: ConsoleCommand.maxCommandLine)
            let block = ConsoleHold.environmentBlock(adding: [ConsoleHold.commandLineVariable: long, "PATH": #"C:\only"#])
            let entries = String(decoding: block, as: UTF16.self).split(separator: "\0").map(String.init)
            #expect(entries.contains("\(ConsoleHold.commandLineVariable)=\(long)"))
            // Replaced, not twice; in order of the names, the drives' folders first.
            #expect(entries.filter { $0.uppercased().hasPrefix("PATH=") } == [#"PATH=C:\only"#])
            func name(_ entry: String) -> String {
                (entry.prefix(1) + (entry.dropFirst().split(separator: "=", maxSplits: 1).first ?? "")).uppercased()
            }
            let names = entries.map(name)
            #expect(names == names.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) })
            #expect(block.suffix(2) == [0, 0])
        }

        /// The prompts' files (`ConsoleCommand.removeStalePrompts`): one no console needs is deleted; one a console
        /// holds open (its program still runs) and one just written (its console not started yet) are kept.
        @Test func aStalePromptIsDeletedAndOneInUseKept() throws {
            let folder = try temporaryFolder("prompts")
            defer { try? FileManager.default.removeItem(at: folder) }
            func file(_ name: String, minutesAgo: Double) throws -> URL {
                let url = folder.appendingPathComponent("agent-prompt-\(name).txt")
                try Data("a prompt".utf8).write(to: url)
                try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-minutesAgo * 60)], ofItemAtPath: url.path)
                return url
            }
            let stale = try file("stale", minutesAgo: 5), held = try file("held", minutesAgo: 5), fresh = try file("fresh", minutesAgo: 0)
            let other = folder.appendingPathComponent("notes.txt")
            try Data("not a prompt".utf8).write(to: other)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-300)], ofItemAtPath: other.path)
            // Held as a console's process holds it.
            let handle = try #require(held.withUnsafeFileSystemRepresentation { path in
                String(cString: path!).withCString(encodedAs: UTF16.self) {
                    CreateFileW($0, GENERIC_READ, DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE), nil, DWORD(OPEN_EXISTING), 0, nil)
                }
            })
            #expect(handle != INVALID_HANDLE_VALUE)
            #expect(ConsoleCommand.removeStalePrompts(in: folder) == ["agent-prompt-stale.txt"])
            #expect(!FileManager.default.fileExists(atPath: stale.path))
            #expect(FileManager.default.fileExists(atPath: held.path) && FileManager.default.fileExists(atPath: fresh.path))
            #expect(FileManager.default.fileExists(atPath: other.path))
            // Still readable while held, as the agent reads it.
            #expect(try String(contentsOf: held, encoding: .utf8) == "a prompt")
            CloseHandle(handle)
            #expect(ConsoleCommand.removeStalePrompts(in: folder) == ["agent-prompt-held.txt"])
        }

        /// The engine, as it starts, deletes the prompts' files an earlier run left (`%TEMP%\AllInOneIME`).
        @Test(.timeLimit(.minutes(1))) func theEngineDeletesStalePromptsAsItStarts() throws {
            try #require(FileManager.default.fileExists(atPath: debugEngine.path), "build the engine first (swift build)")
            let temp = try temporaryFolder("engine-temp")
            defer { try? FileManager.default.removeItem(at: temp) }
            let prompts = temp.appendingPathComponent("AllInOneIME", isDirectory: true)
            try FileManager.default.createDirectory(at: prompts, withIntermediateDirectories: true)
            let stale = prompts.appendingPathComponent("agent-prompt-\(UUID().uuidString).txt")
            try Data("the clipboard's text".utf8).write(to: stale)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-600)], ofItemAtPath: stale.path)
            let config = temp.appendingPathComponent("config.json")
            try Data("{}".utf8).write(to: config)
            let engine = Process()
            engine.executableURL = debugEngine
            engine.arguments = ["--test", "--no-panel", "--no-rime", "--quiet", "--config", config.path]
            var environment = ProcessInfo.processInfo.environment
            environment["TEMP"] = temp.path
            environment["TMP"] = temp.path
            engine.environment = environment
            engine.standardOutput = FileHandle.nullDevice
            engine.standardError = FileHandle.nullDevice
            try engine.run()
            defer { if engine.isRunning { engine.terminate() } }
            let deadline = Date().addingTimeInterval(15)
            while FileManager.default.fileExists(atPath: stale.path), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            #expect(!FileManager.default.fileExists(atPath: stale.path))
        }
    }
}
#endif
