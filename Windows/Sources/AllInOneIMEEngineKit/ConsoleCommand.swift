#if os(Windows)
import AllInOneIMECore
import Foundation

/// A program to start in a console window of its own (`@agent`, an `@question` conversation handed to an agent, a
/// `terminal` command): what `CreateProcessW` is given. No shell in between, so nothing in a prompt is ever code:
///
/// - the program is found as cmd.exe finds one (`WindowsPrograms.find`: on the PATH, PATHEXT's extensions added,
///   never in the current folder): `claude` is claude.exe, or npm's claude.cmd; a relative path (`.\tools\x.cmd`) is
///   in the folder the program runs in (the home folder), not the engine's current folder;
/// - a .exe gets its arguments quoted as the C runtime reads them back (`WindowsCommandLine`); a .bat or .cmd goes
///   through cmd.exe with its arguments escaped so that cmd.exe runs and expands nothing in them (BatBadBut,
///   CVE-2024-24576); a script through its interpreter (`WindowsPrograms.invocation`);
/// - a prompt the command line can't carry goes in a file, and the agent is asked to read it: one longer than
///   Windows' command line (32,767 characters) or cmd.exe's (8,191), or one with a line break for a batch file (cmd.exe
///   would end the command there). Never cut, never refused for its length.
public struct ConsoleCommand: Equatable {
    /// The program `CreateProcessW` starts (cmd.exe for a batch file).
    public var application: String
    /// Its command line.
    public var commandLine: String
    /// The file the prompt went in, when it couldn't go on the command line.
    public var promptFile: URL?

    /// `CreateProcessW`'s limit, 32,767 characters with the NUL at the end.
    public static let maxCommandLine = 32_766
    /// cmd.exe's: the longest command it runs.
    public static let maxBatchCommandLine = 8_191

    /// `argv` (the program first), and `prompt` after it as its last argument when there is one. `path`: the PATH the
    /// program is looked for in; `directory`: the folder it runs in, where a relative path to it starts;
    /// `promptFolder`: where a prompt too long for the command line goes.
    public static func make(_ argv: [String], prompt: String? = nil, path: String?, directory: URL = CorePaths.home,
                            promptFolder: URL) throws -> ConsoleCommand {
        guard let program = argv.first, !program.isEmpty else { throw SystemActionError("No program to run") }
        guard let file = WindowsPrograms.find(program, path: path, directory: directory, expandingTilde: true)?.standardizedFileURL else {
            throw SystemActionError("Couldn't find \(program): is it installed, and on the PATH?")
        }
        let arguments = Array(argv.dropFirst())
        let limit = WindowsPrograms.kind(of: file) == .batch ? maxBatchCommandLine : maxCommandLine
        func invocation(_ last: String?) throws -> WindowsPrograms.Invocation? {
            let invocation = try WindowsPrograms.invocation(of: file, arguments: arguments + (last.map { [$0] } ?? []), environment: nil)
            return invocation.commandLine.utf16.count <= limit ? invocation : nil
        }
        do {
            if let fits = try invocation(prompt) { return ConsoleCommand(application: fits.application, commandLine: fits.commandLine) }
        } catch WindowsLaunchError.invalidArgument where prompt != nil {
            // A line break (or a NUL) for a batch file: the prompt goes in a file, as below.
        }
        guard let prompt else { throw SystemActionError("The command is too long for a Windows command line") }
        let promptFile = try write(prompt, in: promptFolder)
        do {
            guard let fits = try invocation(reference(to: promptFile)) else {
                throw SystemActionError("The command is too long for a Windows command line")
            }
            return ConsoleCommand(application: fits.application, commandLine: fits.commandLine, promptFile: promptFile)
        } catch {
            try? FileManager.default.removeItem(at: promptFile)
            throw error
        }
    }

    /// What the agent is given in place of a prompt that went in `file`.
    public static func reference(to file: URL) -> String {
        "The request is in the file \(file.withUnsafeFileSystemRepresentation { String(cString: $0!) }): read it, and do what it asks."
    }

    /// `prompt` in a new file in `folder` (UTF-8), in the user's own temporary folder. Those of earlier launches go
    /// after a day: an agent reads its prompt as it starts.
    static func write(_ prompt: String, in folder: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let dayAgo = Date().addingTimeInterval(-86_400)
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix("agent-prompt-") && name.hasSuffix(".txt") {
            let old = folder.appendingPathComponent(name)
            if let modified = (try? fm.attributesOfItem(atPath: old.path))?[.modificationDate] as? Date, modified < dayAgo {
                try? fm.removeItem(at: old)
            }
        }
        let file = folder.appendingPathComponent("agent-prompt-\(UUID().uuidString).txt")
        try Data(prompt.utf8).write(to: file, options: .withoutOverwriting)
        return file
    }

    /// Where a prompt too long for the command line goes: `%TEMP%\AllInOneIME`.
    public static var defaultPromptFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("AllInOneIME", isDirectory: true)
    }
}
#endif
