import AllInOneIMECore
import Foundation
import Testing

// Issue #49: Settings search lists "Your English words" when no input shows that section. The English words pinyin
// offers are drawn in an input's chip only for English, or for Chinese without English (SettingsWindow's
// `inputOptions`). The sidebar's search (`SettingsSpot.search`, with the window's config) leaves out the rows the
// config doesn't show (`isShown`), but has nothing to say about the English words: with French (or Korean, Hindi) as
// the only input languages, searching "english words" or "英文词" still lists them, and picking the result outlines
// the input languages' row with no English words section anywhere on the page. Expected: the result is hidden whenever
// the section isn't drawn, and still found whenever it is.
//
// The input method's own code can't be imported here (it is an executable target): all of Sources/AllInOneIME is
// compiled into a child process, with the Mac library, the core and librime, as the input method is built. Only
// main.swift's dispatch (what follows `let arguments = …`) is replaced: the child searches the settings as the
// sidebar does (`SettingsSpot.search(typed, trigger: config.commandTrigger, config: config)`), with the input
// languages the test gives, in each interface language, and prints what each search lists. The child's home is a
// folder of the test's: nothing reads the user's config.

@Suite(.serialized)
struct Issue49Tests {
    /// Input languages with neither English nor Chinese: no chip draws the English words.
    static let withoutTheSection: [[Language]] = [[.french], [.korean], [.hindi], [.french, .korean], [.korean, .hindi, .french]]
    /// Input languages with English, or Chinese without English: a chip draws them.
    static let withTheSection: [[Language]] = [[.english], [.chinese], [.chinese, .english], [.english, .chinese], [.french, .english],
                                               [.chinese, .french], [.korean, .chinese]]

    /// French (Korean, Hindi) the only input languages: searching "english words" or "英文词", in either interface
    /// language, never lists "Your English words", which no input's chip shows.
    @Test(arguments: withoutTheSection)
    func theEnglishWordsAreNotFoundWhenNoInputShowsThem(_ languages: [Language]) throws {
        let report = try Issue49Child.run(languages)
        #expect(report.searches.count == Issue49Child.searches.count, "the child didn't search every time: \(report)")
        for search in report.searches {
            let searched = "input languages \(Issue49Child.names(languages)), interface \(search.interface): searching \"\(search.query)\""
            #expect(!search.found.contains(.englishWords),
                    "\(searched) lists \"Your English words\", but no input shows that section: \(search.found.map(\.rawValue))")
        }
    }

    /// English among the input languages, or Chinese without English: the same searches still find the English words,
    /// which a chip shows.
    @Test(arguments: withTheSection)
    func theEnglishWordsAreFoundWhenAnInputShowsThem(_ languages: [Language]) throws {
        let report = try Issue49Child.run(languages)
        #expect(report.searches.count == Issue49Child.searches.count, "the child didn't search every time: \(report)")
        for search in report.searches {
            let searched = "input languages \(Issue49Child.names(languages)), interface \(search.interface): searching \"\(search.query)\""
            #expect(search.found.contains(.englishWords),
                    "\(searched) doesn't list \"Your English words\", which a chip shows: \(search.found.map(\.rawValue))")
        }
    }
}

enum Issue49Child {
    /// What the user searches the settings for, and in which interface language (config `uiLanguage`).
    static let searches: [(interface: String, query: String)] = [
        ("en", "english words"), ("en", "英文词"), ("zh", "english words"), ("zh", "英文词"),
    ]

    /// A search's rows, as the child printed them.
    struct Search {
        var interface: String
        var query: String
        var found: [Spot]
    }

    /// A row, for the input method's `SettingsSpot` (which can't be imported): its raw value.
    struct Spot: RawRepresentable, Hashable {
        var rawValue: String
        static let englishWords = Spot(rawValue: "englishWords")
    }

    struct Report: CustomStringConvertible {
        var searches: [Search]
        var status: Int32
        var output: String
        var description: String { "(the child exited \(status)):\n\(output)" }
    }

    struct Failure: Error, CustomStringConvertible { var description: String }

    static func names(_ languages: [Language]) -> String { languages.map(\.englishName).joined(separator: ", ") }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    static var thirdParty: URL {
        ProcessInfo.processInfo.environment["ALLINONEIME_THIRDPARTY"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("ThirdParty")
    }

    /// The searches, with `languages` the input languages (in this order, the first the default, as the settings set
    /// them: `Config.setOrder`).
    static func run(_ languages: [Language]) throws -> Report {
        let executable = try compiled.get()
        let fm = FileManager.default
        // The child's home: never the user's config.
        let home = fm.temporaryDirectory.appendingPathComponent("issue49-home-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let arguments = [languages.map(\.rawValue).joined(separator: ",")] + searches.flatMap { [$0.interface, $0.query] }
        let result = try command(executable, arguments, environment: ["CFFIXED_USER_HOME": home.path, "HOME": home.path], timeout: 60)
        let found = result.output.split(separator: "\n").filter { $0.hasPrefix("FOUND\t") }.compactMap { line -> Search? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4 else { return nil }
            return Search(interface: fields[1], query: fields[2],
                          found: fields[3].split(separator: ",").map { Spot(rawValue: String($0)) })
        }
        return Report(searches: found, status: result.status, output: result.output)
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("issue49-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        // main.swift as written up to its dispatch, then the harness.
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.upperBound]) + Issue49Harness.swift).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        // The Mac library, the core and librime's wrapper, as `swift test` built them.
        let products = repository.appendingPathComponent(".build/debug")
        let modules = fm.fileExists(atPath: products.appendingPathComponent("Modules").path)
            ? products.appendingPathComponent("Modules") : products
        var objects: [String] = []
        for module in ["AllInOneIMEMac", "AllInOneIMECore", "AllInOneIMERime", "AllInOneIMEText", "AllInOneIMEScriptEngine",
                       "CQuickJS", "Crypto"] {
            let aggregate = products.appendingPathComponent(module + ".o")
            if fm.fileExists(atPath: aggregate.path) {
                objects.append(aggregate.path)
            } else if let files = try? fm.contentsOfDirectory(at: products.appendingPathComponent(module + ".build"), includingPropertiesForKeys: nil) {
                objects += files.filter { $0.pathExtension == "o" }.map(\.path)
            }
        }
        let rimeLib = thirdParty.appendingPathComponent("librime/dist/lib")
        let executable = scratch.appendingPathComponent("issue49")
        let arguments = ["swiftc", "-swift-version", "5", "-j", "\(max(2, ProcessInfo.processInfo.activeProcessorCount))",
                         "-I", modules.path, "-I", repository.appendingPathComponent("Core/Sources/CRime").path,
                         "-L", rimeLib.path, "-lrime", "-Xlinker", "-rpath", "-Xlinker", rimeLib.path,
                         "-framework", "AppKit", "-framework", "InputMethodKit", "-framework", "Carbon", "-framework", "AVFoundation",
                         "-framework", "Speech", "-framework", "EventKit", "-framework", "SwiftUI",
                         "-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels",
                         mainFile.path] + others + objects + ["-o", executable.path]
        let swift = try command(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments, timeout: 900)
        guard swift.status == 0 else { throw Failure(description: "compiling Sources/AllInOneIME with the harness:\n\(swift.output)") }
        return executable
    }

    private static func command(_ executable: URL, _ arguments: [String], environment: [String: String] = [:],
                                timeout: TimeInterval) throws -> (status: Int32, output: String) {
        // A file, not a pipe: a long compiler output never blocks the child.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("issue49-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: log)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = repository
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.5)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw Failure(description: "timed out: \(executable.lastPathComponent) \(arguments.first ?? "")\n"
                          + ((try? String(contentsOf: log, encoding: .utf8)) ?? ""))
        }
        return (process.terminationStatus, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }
}

/// What follows main.swift's `let arguments = …` in the child: the input languages (raw values, comma-separated), then
/// pairs of an interface language and a query; each searched as the sidebar searches, one `FOUND` line each.
private enum Issue49Harness {
    static let swift = #"""

// MARK: - Issue #49's child (in place of main.swift's dispatch)

MainActor.assumeIsolated {
    // Never the user's config: the test's home.
    let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
    guard !home.isEmpty, Config.defaultURL.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
        print("FAIL the config file isn't in the test's home: \(Config.defaultURL.path)")
        exit(3)
    }
    guard let first = arguments.first, arguments.count % 2 == 1 else {
        print("FAIL usage: LANGUAGES [INTERFACE QUERY]…")
        exit(2)
    }
    let languages = first.split(separator: ",").compactMap { Language(rawValue: String($0)) }
    var config = Config.default
    config.setOrder(languages)
    guard config.inputLanguages == languages else {
        print("FAIL the input languages are \(config.inputLanguages), not \(languages)")
        exit(3)
    }
    for pair in stride(from: 1, to: arguments.count, by: 2) {
        let interface = arguments[pair], query = arguments[pair + 1]
        config.uiLanguage = interface
        UIText.choice = interface
        // As the sidebar searches (SettingsWindow: what is typed in its search field, with the window's config).
        let found = SettingsSpot.search(query, trigger: config.commandTrigger, config: config)
        print("FOUND\t\(interface)\t\(query)\t\(found.map(\.rawValue).joined(separator: ","))")
    }
    fflush(stdout)
}
exit(0)
"""#
}
