import Foundation

/// Compiles app sources into a test child using the libraries built by SwiftPM.
///
/// A few compiles at a time (`turns`), each timed from its own start. The suites that compile a child (some 35) start
/// together, each on its first test, and the compiles of the whole app among them use every core (`-j`): all at once,
/// with the machine busy besides (CI's other tests, another checkout's build), a compile timed from when it was asked
/// for waited on all the others, and a harness of a few files failed at its 60 or 90 seconds ("timed out: swiftc";
/// reproduced: every suite's compile timed out, the 900-second ones too). Two compiles of the whole app already keep
/// every core busy; more at once only make each slower. A compile that waited for its turn says so when it times out.
public enum SourceCompiler {
    private static let turns = DispatchSemaphore(value: 2)

    public static func compile(repository: URL, sources: [String], extraObjects: [String] = [],
                               executable: URL, parseAsLibrary: Bool = false,
                               timeout: TimeInterval) throws -> (status: Int32, output: String) {
        let products = try productsDirectory(repository: repository)
        let modules = FileManager.default.fileExists(atPath: products.appendingPathComponent("Modules").path)
            ? products.appendingPathComponent("Modules") : products
        let thirdParty = ProcessInfo.processInfo.environment["ALLINONEIME_THIRDPARTY"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("ThirdParty")
        let rimeLib = thirdParty.appendingPathComponent("librime/dist/lib")
        let testingFrameworks = URL(fileURLWithPath: try platformPath(repository: repository))
            .appendingPathComponent("Developer/Library/Frameworks")
        var arguments = ["swiftc", "-swift-version", "5"]
        if parseAsLibrary {
            arguments.append("-parse-as-library")
        } else {
            arguments += ["-j", "\(max(2, ProcessInfo.processInfo.activeProcessorCount))"]
        }
        arguments += ["-I", modules.path, "-I", repository.appendingPathComponent("Core/Sources/CRime").path,
                      "-L", rimeLib.path, "-lrime", "-Xlinker", "-rpath", "-Xlinker", rimeLib.path,
                      "-F", testingFrameworks.path, "-Xlinker", "-rpath", "-Xlinker", testingFrameworks.path]
        let frameworks = ["AppKit", "InputMethodKit", "Carbon", "AVFoundation", "Speech", "EventKit", "SwiftUI", "Testing"]
        for framework in frameworks {
            arguments += ["-framework", framework]
        }
        arguments += ["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"]
        arguments += sources + extraObjects + (try libraryObjects(in: products)) + ["-o", executable.path]
        Scratch.removeAtExit(executable)
        try copyCoreResources(from: products, besides: executable)
        let asked = Date()
        turns.wait()
        defer { turns.signal() }
        return try run(arguments, repository: repository, timeout: timeout, waited: Date().timeIntervalSince(asked))
    }

    /// The SDK's platform folder (for Swift Testing's frameworks), asked of xcrun once for every compile: asked by each
    /// at once, its 30 seconds ran out too on a busy machine.
    private static func platformPath(repository: URL) throws -> String {
        try platform.withLock { known in
            if let known { return known }
            let asked = try run(["--show-sdk-platform-path"], repository: repository, timeout: 30)
            guard asked.status == 0 else { throw CompileError(asked.output) }
            let path = asked.output.trimmingCharacters(in: .whitespacesAndNewlines)
            known = path
            return path
        }
    }
    private static let platform = PlatformPath()

    private final class PlatformPath: @unchecked Sendable {
        private let lock = NSLock()
        private var path: String?

        func withLock<T>(_ body: (inout String?) throws -> T) rethrows -> T {
            lock.lock()
            defer { lock.unlock() }
            return try body(&path)
        }
    }

    /// The core's resources (its English words: `CoreResources` in the core) beside the child, as SwiftPM puts them
    /// beside the binaries it builds: without them the child would know no English word.
    private static func copyCoreResources(from products: URL, besides executable: URL) throws {
        let fm = FileManager.default
        let resources = products.appendingPathComponent("AllInOneIME-Core_AllInOneIMECore.bundle")
        let copy = executable.deletingLastPathComponent().appendingPathComponent(resources.lastPathComponent)
        guard fm.fileExists(atPath: resources.path), !fm.fileExists(atPath: copy.path) else { return }
        try fm.copyItem(at: resources, to: copy)
    }

    private static func productsDirectory(repository: URL) throws -> URL {
        let build = repository.appendingPathComponent(".build")
        // SwiftPM holds its build lock until the tests exit, so asking it for --show-bin-path here would deadlock.
        let testBundle = Bundle.allBundles.first { $0.bundleURL.lastPathComponent == "AllInOneIMEMacTests.xctest" }
        let candidates = [testBundle?.bundleURL.deletingLastPathComponent(),
                          build.appendingPathComponent("debug").resolvingSymlinksInPath(),
                          build.appendingPathComponent("out/Products/Debug")].compactMap { $0 }
        for candidate in candidates {
            let entries = try? FileManager.default.contentsOfDirectory(at: candidate, includingPropertiesForKeys: nil)
            if entries?.contains(where: { $0.pathExtension == "o" || $0.pathExtension == "build" }) == true {
                return candidate
            }
        }
        throw CompileError("no build products found in \(candidates.map(\.path).joined(separator: ", "))")
    }

    private static func libraryObjects(in products: URL) throws -> [String] {
        let fm = FileManager.default
        let entries = try fm.contentsOfDirectory(at: products, includingPropertiesForKeys: nil)
            .sorted { $0.path < $1.path }
        var objects = entries.filter { $0.pathExtension == "o" }.map(\.path)
        let aggregates = Set(entries.filter { $0.pathExtension == "o" }
            .map { $0.deletingPathExtension().lastPathComponent })
        for folder in entries where folder.pathExtension == "build" {
            let module = folder.deletingPathExtension().lastPathComponent
            if aggregates.contains(module) || module.hasSuffix("Tests") ||
                fm.isExecutableFile(atPath: products.appendingPathComponent(module).path) { continue }
            let files = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            objects += files.filter { $0.pathExtension == "o" }.map(\.path).sorted()
        }
        guard !objects.isEmpty else { throw CompileError("no library objects in \(products.path)") }
        return objects
    }

    private static func run(_ arguments: [String], repository: URL, timeout: TimeInterval,
                            waited: TimeInterval = 0) throws -> (status: Int32, output: String) {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("source-compiler-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: log)
        }
        // swiftc's own temporary files (TemporaryDirectory.*, which it left behind) in a folder removed with the log.
        let driverTemp = FileManager.default.temporaryDirectory
            .appendingPathComponent("source-compiler-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: driverTemp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: driverTemp) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["TMPDIR": driverTemp.path + "/"]) { $1 }
        process.currentDirectoryURL = repository
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.5)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            let turn = waited >= 1 ? ", after waiting \(Int(waited)) s for its turn" : ""
            throw CompileError("timed out: \(arguments.prefix(2).joined(separator: " ")) (\(Int(timeout)) s\(turn))\n"
                               + ((try? String(contentsOf: log, encoding: .utf8)) ?? ""))
        }
        return (process.terminationStatus, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }

    /// The folders the compiled children were written to, removed when the test process exits: each is a harness
    /// compiled from the sources (10 to 54 MB), made once per suite and run by its tests until the end, and they were
    /// never removed (246,000 test folders filled the Mac mini's disk, 2026-11-16). Only a folder directly in the
    /// temporary directory, never the temporary directory itself.
    private final class Scratch: @unchecked Sendable {
        static let shared = Scratch()
        private let lock = NSLock()
        private var folders: Set<String> = []
        private var registered = false

        static func removeAtExit(_ executable: URL) {
            let folder = executable.deletingLastPathComponent().standardizedFileURL
            let temporary = FileManager.default.temporaryDirectory.standardizedFileURL
            guard folder.deletingLastPathComponent().path == temporary.path, folder.path != temporary.path else { return }
            shared.lock.lock()
            defer { shared.lock.unlock() }
            shared.folders.insert(folder.path)
            if !shared.registered {
                shared.registered = true
                atexit { Scratch.shared.removeAll() }
            }
        }

        private func removeAll() {
            lock.lock()
            let all = folders
            lock.unlock()
            for folder in all { try? FileManager.default.removeItem(atPath: folder) }
        }
    }

    private struct CompileError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
