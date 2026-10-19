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
        /// still there after it, the output and "exited with code 3" on its screen; a key closes it.
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
            #expect(probe.pressKey(pid))
            #expect(WaitForSingleObject(process, 5000) == WAIT_OBJECT_0)
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
    }
}
#endif
