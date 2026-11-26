import AllInOneIMETestSupport
import Foundation

// The child process of the Review076…Tests suites in this folder (the 0.7.6 review's items 12 to 24 that live in the
// input method's own code). Sources/AllInOneIME is an executable target and can't be imported: as ControllerOffMainTests
// and Issue40Tests do it, all of it is compiled once into a child with main.swift's dispatch (what follows
// `let arguments = …`) replaced by the harness below, and each test runs the child in one `way`. The child's home is a
// folder of the test's, its keychain an in-memory one, Apple's model a stub that isn't available; its fields are its
// own objects, the panel and the gray text are drawn invisible, and no key tap is made: nothing is typed into an app,
// nothing leaves the Mac.
//
// Which thread opens a file (items 12 and 17) is told by a small library the child is started with
// (`DYLD_INSERT_LIBRARIES`), which interposes `open` and `openat` and writes a line for each file whose path ends as
// one of those watched: "main" or "other", and the path. Nothing in the input method's code is changed for it.

enum Review076P2Child {
    struct Failure: Error, CustomStringConvertible { var description: String }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<(executable: URL, hook: URL), Error> = Result { try compile() }

    /// What the child told in `way`: its "KV key value" lines, and the files opened among those watched (`opened`).
    struct Report: CustomStringConvertible {
        var values: [String: String]
        /// Each watched file opened: on the main thread or not, and its path.
        var opened: [(main: Bool, path: String)]
        var output: String

        subscript(key: String) -> String? { values[key] }
        var description: String {
            values.keys.sorted().map { "\($0)=\(values[$0] ?? "")" }.joined(separator: ", ")
                + (opened.isEmpty ? "" : "; opened: " + opened.map { ($0.main ? "main " : "other ") + $0.path }.joined(separator: ", "))
        }
    }

    static func run(_ way: String, timeout: TimeInterval = 90) throws -> Report {
        let (executable, hook) = try compiled.get()
        let fm = FileManager.default
        let home = TestScratch.temporary("review076p2-home-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let opens = home.appendingPathComponent("opened.log")
        let log = home.appendingPathComponent("output.log")
        fm.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = [way]
        process.currentDirectoryURL = repository
        process.environment = ProcessInfo.processInfo.environment.merging([
            "CFFIXED_USER_HOME": home.path, "HOME": home.path,
            "AWS_CONFIG_FILE": "/nonexistent", "AWS_SHARED_CREDENTIALS_FILE": "/nonexistent",
            "ALLINONEIME_LOGIN_SHELL_TIMEOUT": "2",
            "DYLD_INSERT_LIBRARIES": hook.path,
            "REVIEW076_OPEN_LOG": opens.path,
        ]) { $1 }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        let output = { (try? String(contentsOf: log, encoding: .utf8)) ?? "" }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.5)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw Failure(description: "the child (\(way)) didn't finish in \(Int(timeout)) s:\n\(output())")
        }
        let status = process.terminationReason == .uncaughtSignal ? 128 + process.terminationStatus : process.terminationStatus
        guard status == 0 else { throw Failure(description: "the child (\(way)) failed (\(status)):\n\(output())") }
        var values: [String: String] = [:]
        for line in output().split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3, fields[0] == "KV", let decoded = Data(base64Encoded: fields[2]) else { continue }
            values[fields[1]] = String(decoding: decoded, as: UTF8.self)
        }
        guard !values.isEmpty else { throw Failure(description: "the child (\(way)) told nothing:\n\(output())") }
        let opened = ((try? String(contentsOf: opens, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { line -> (Bool, String)? in
            let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
            return fields.count == 2 ? (fields[0] == "main", fields[1]) : nil
        }
        return Report(values: values, opened: opened, output: output())
    }

    private static func compile() throws -> (executable: URL, hook: URL) {
        let fm = FileManager.default
        let scratch = TestScratch.temporary("review076p2-child-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.upperBound]) + Review076P2Harness.swift).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.sorted { $0.path < $1.path }
            .map { source -> String in
                guard source.lastPathComponent == "TerminalLauncher.swift" else { return source.path }
                let text = try String(contentsOf: source, encoding: .utf8)
                    .replacingOccurrences(of: "private static func runWhenReady(", with: "static func runWhenReady(")
                let copy = scratch.appendingPathComponent("TerminalLauncher.swift")
                try text.write(to: copy, atomically: true, encoding: .utf8)
                return copy.path
            }
        let executable = scratch.appendingPathComponent("review076p2")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
                                               executable: executable, timeout: 900)
        guard swift.status == 0 else {
            let errors = swift.output.split(separator: "\n").filter { $0.contains("error:") }
            throw Failure(description: "compiling Sources/AllInOneIME with the harness:\n"
                          + (errors.isEmpty ? swift.output : errors.joined(separator: "\n")))
        }
        // The library that tells which thread opens a watched file.
        let hookSource = scratch.appendingPathComponent("opens.c"), hook = scratch.appendingPathComponent("opens.dylib")
        try Review076P2Harness.opens.write(to: hookSource, atomically: true, encoding: .utf8)
        let clang = try command(["clang", "-dynamiclib", "-O1", hookSource.path, "-o", hook.path], timeout: 120)
        guard clang.status == 0 else { throw Failure(description: "compiling the open hook:\n\(clang.output)") }
        return (executable, hook)
    }

    private static func command(_ arguments: [String], timeout: TimeInterval) throws -> (status: Int32, output: String) {
        let log = TestScratch.temporary("review076p2-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: log)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            throw Failure(description: "timed out: \(arguments.prefix(2).joined(separator: " "))")
        }
        return (process.terminationStatus, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }
}

enum Review076P2Harness {
    /// `open` and `openat` interposed: a line in $REVIEW076_OPEN_LOG for each path ending in a watched name.
    static let opens = #"""
    #include <fcntl.h>
    #include <pthread.h>
    #include <stdarg.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <unistd.h>

    static int ends(const char *path, const char *name) {
        size_t a = strlen(path), b = strlen(name);
        return a >= b && strcmp(path + a - b, name) == 0;
    }

    static void note(const char *path) {
        if (!path || !(ends(path, "/RedactionWords.txt") || ends(path, "/config.json"))) return;
        const char *log = getenv("REVIEW076_OPEN_LOG");
        if (!log) return;
        int fd = open(log, O_WRONLY | O_APPEND | O_CREAT, 0600);
        if (fd < 0) return;
        char line[2200];
        int n = snprintf(line, sizeof line, "%s\t%s\n", pthread_main_np() ? "main" : "other", path);
        if (n > 0) (void)write(fd, line, (size_t)n);
        close(fd);
    }

    static int hooked_open(const char *path, int flags, ...) {
        mode_t mode = 0;
        if (flags & O_CREAT) { va_list ap; va_start(ap, flags); mode = (mode_t)va_arg(ap, int); va_end(ap); }
        note(path);
        return open(path, flags, mode);
    }

    static int hooked_openat(int at, const char *path, int flags, ...) {
        mode_t mode = 0;
        if (flags & O_CREAT) { va_list ap; va_start(ap, flags); mode = (mode_t)va_arg(ap, int); va_end(ap); }
        note(path);
        return openat(at, path, flags, mode);
    }

    __attribute__((used)) static struct { const void *replacement; const void *replacee; } interposers[]
        __attribute__((section("__DATA,__interpose"))) = {
        { (const void *)hooked_open, (const void *)open },
        { (const void *)hooked_openat, (const void *)openat },
    };
    """#

    /// After main.swift's `let arguments = …`.
    static let swift = swiftA + swiftB + swiftC
}
