import Foundation

/// Compiles app sources into a test child using the libraries built by SwiftPM.
public enum SourceCompiler {
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
        let platform = try run(["--show-sdk-platform-path"], repository: repository, timeout: 30)
        guard platform.status == 0 else { throw CompileError(platform.output) }
        let testingFrameworks = URL(fileURLWithPath: platform.output.trimmingCharacters(in: .whitespacesAndNewlines))
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
        return try run(arguments, repository: repository, timeout: timeout)
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

    private static func run(_ arguments: [String], repository: URL,
                            timeout: TimeInterval) throws -> (status: Int32, output: String) {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("source-compiler-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: log)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
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
            throw CompileError("timed out: \(arguments.prefix(2).joined(separator: " "))\n"
                               + ((try? String(contentsOf: log, encoding: .utf8)) ?? ""))
        }
        return (process.terminationStatus, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }

    private struct CompileError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
