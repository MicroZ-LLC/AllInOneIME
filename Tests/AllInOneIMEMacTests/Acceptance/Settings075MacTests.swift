import AllInOneIMECore
import Foundation
import Testing

// 0.7.5 settings: lighter, one place for AI commands (owner-approved 2026-11-12/13), the Mac window's side. The
// acceptance tests, written from the spec by an author other than the implementation's (whose changes don't edit them);
// the core's side is Core/Tests/AllInOneIMECoreTests/Acceptance/Settings075Tests.swift.
//
// What the spec moves is the Mac window's (SwiftUI, Sources/AllInOneIME), not the core's settings document's (Windows'
// window, whose sections the spec doesn't name). These tests look at it as the sidebar's search does
// (`SettingsSpot.search(typed, trigger:, config:)`), which "finds each moved control on its new page" (spec 1) and
// "points there" (spec 2), and at the page each row is on (`SettingsSpot.page`):
//   1. @improve's options (its styles, whether it also translates, the jargon list), @translate's languages and
//      @question's options (where a conversation goes on, the recent questions) are on the AI page, found there by
//      their titles in both interface languages and by the command's name; Commands keeps @agent, notes, plugins and
//      extensions.
//   2. "Recent questions" (「最近的问题」) is found in one place, the AI page.
//   4. "Use the selected text" has no row while it is on (the default); off in the config, its Restore Default row is
//      found, on Advanced, where its switch was.
//   7. @search's row (Web Search, the Brave key) is gone.
// Not seen here: the order on the AI page (the AI picker, then AI commands, then the model parameters), the section's
// title, what Restore Default does, the iCloud section's one Remove from iCloud… and the help texts' length.
//
// The input method's own code can't be imported here (it is an executable target): as Issue49Tests does it, all of
// Sources/AllInOneIME is compiled into a child process, with the Mac library, the core and librime, as the input method
// is built. Only main.swift's dispatch (what follows `let arguments = …`) is replaced: the child searches the settings
// as the sidebar does, with the config each test gives, in each interface language, and prints what each search lists
// and on which page. The child's home is a folder of the test's: nothing reads the user's config.

@Suite(.serialized)
struct Settings075MacTests {
    typealias Ask = Settings075Child.Ask

    /// The interface languages (config `uiLanguage`).
    static let interfaces = ["en", "zh"]
    /// The AI commands' rows: @improve's, @translate's, @question's (its recent questions too).
    static let aiCommands = ["rewriteStyles", "improveTranslates", "jargonList", "outputLanguages", "questionContinueIn",
                             "rememberQuestions"]
    /// The Commands page's rows that aren't AI commands: they stay there.
    static let commandsRows = ["customCommands", "agent", "notes", "plugins", "scriptExtensions", "extensionSources"]

    /// "Settings → AI: … a new section 'AI commands' holding the options of @improve, @translate and @question, moved from
    /// General's writing section and from the Commands page … Commands keeps the non-AI items": each row on its page.
    @Test func theAICommandsRowsAreOnTheAIPage() throws {
        let report = try Settings075Child.run((Self.aiCommands + Self.commandsRows).map { Ask(.plain, "en", "page:" + $0) })
        for row in Self.aiCommands {
            #expect(report.page(row) == "ai", "\(row) is on \(report.page(row) ?? "no page"): \(report)")
        }
        for row in Self.commandsRows {
            #expect(report.page(row) == "commands", "\(row) is on \(report.page(row) ?? "no page"): \(report)")
        }
    }

    /// "The settings search finds each moved control on its new page": each by its own title, in both interface languages
    /// (the jargon list shown: a list named), and by the command it belongs to.
    @Test func theSearchFindsEachMovedRowOnTheAIPage() throws {
        var asks: [Ask] = []
        for interface in Self.interfaces {
            asks += Self.aiCommands.map { Ask(.jargon, interface, "title:" + $0) }
            asks += ["@improve", "@translate", "@question"].map { Ask(.jargon, interface, $0) }
        }
        let report = try Settings075Child.run(asks)
        for interface in Self.interfaces {
            for row in Self.aiCommands {
                let found = report.found(Ask(.jargon, interface, "title:" + row))
                #expect(found?.contains(.init(row, "ai")) == true, "\(interface): searching \(row)'s title lists \(found ?? []): \(report)")
            }
            for (command, rows) in [("@improve", ["rewriteStyles", "improveTranslates"]), ("@translate", ["outputLanguages"]),
                                    ("@question", ["questionContinueIn", "rememberQuestions"])] {
                let found = report.found(Ask(.jargon, interface, command))
                for row in rows {
                    #expect(found?.contains(.init(row, "ai")) == true, "\(interface): searching \(command) lists \(found ?? []): \(report)")
                }
            }
        }
    }

    /// "'最近的问题' / 'Recent questions' in one place: … keep one (on the AI page, in the AI commands section, with
    /// @question), and the search points there": searching for them (in either language, and by the row's title in the
    /// interface's) lists Remember recent questions, on the AI page, and nothing on another page.
    @Test func recentQuestionsAreFoundInOnePlace() throws {
        let queries = ["recent questions", "最近的问题", "title:rememberQuestions"]
        let asks = Self.interfaces.flatMap { interface in queries.map { Ask(.plain, interface, $0) } }
        let report = try Settings075Child.run(asks)
        for ask in asks {
            let found = try #require(report.found(ask), "\(ask) not searched: \(report)")
            #expect(found.contains(.init("rememberQuestions", "ai")), "\(ask): \(found)")
            #expect(found.allSatisfy { $0.page == "ai" }, "\(ask) lists a row on another page: \(found)")
        }
    }

    /// "'Use the selection' (`useSelection`) … the toggle leaves the window": on (the default), searching for it finds
    /// nothing; off in the config, "a 'restore default' row in its place": found, on Advanced, where its switch was.
    @Test func theUseSelectionRowIsFoundOnlyWhileItIsOff() throws {
        let queries = ["selected text", "选中", "title:useSelection"]
        var asks: [Ask] = []
        for config in [Settings075Child.Variant.plain, .selectionOff] {
            asks += Self.interfaces.flatMap { interface in queries.map { Ask(config, interface, $0) } }
        }
        let report = try Settings075Child.run(asks)
        for ask in asks {
            let found = try #require(report.found(ask), "\(ask) not searched: \(report)")
            let rows = found.filter { $0.row == "useSelection" }
            if ask.variant == .plain {
                #expect(rows.isEmpty, "\(ask): on, it has no row: \(found)")
            } else {
                #expect(rows == [.init("useSelection", "advanced")], "\(ask): \(found)")
            }
        }
    }

    /// "Delete @search (… the Brave key settings …)": no row of the window is its (0.7.4's `webSearch`), and searching for
    /// it lists none.
    @Test func theWebSearchRowIsGone() throws {
        let queries = ["@search", "brave", "web search", "网页搜索"]
        let asks = [Ask(.plain, "en", "page:webSearch")] + Self.interfaces.flatMap { interface in queries.map { Ask(.plain, interface, $0) } }
        let report = try Settings075Child.run(asks)
        #expect(report.page("webSearch") == "none", "\(report)")
        for ask in asks.dropFirst() {
            let found = try #require(report.found(ask), "\(ask) not searched: \(report)")
            #expect(!found.contains { $0.row == "webSearch" }, "\(ask): \(found)")
        }
    }
}

enum Settings075Child {
    /// The config a search is made with: the default (Chinese and English typed); with a jargon list named (its row
    /// shown); with `useSelection` off.
    enum Variant: String, Sendable {
        case plain, jargon, selectionOff
    }

    /// What the child is asked: a search (`query`: what is typed, or "title:<row>", the row's own title in the interface
    /// language) or a row's page ("page:<row>").
    struct Ask: Hashable, CustomStringConvertible, Sendable {
        var variant: Variant
        var interface: String
        var query: String
        init(_ variant: Variant, _ interface: String, _ query: String) { (self.variant, self.interface, self.query) = (variant, interface, query) }
        var argument: String { [variant.rawValue, interface, query].joined(separator: "\t") }
        var description: String { "\(variant.rawValue), interface \(interface): \"\(query)\"" }
    }

    /// A row found, for the input method's `SettingsSpot` (which can't be imported): its raw value, and its page's.
    struct Found: Hashable, CustomStringConvertible {
        var row: String
        var page: String
        init(_ row: String, _ page: String) { (self.row, self.page) = (row, page) }
        var description: String { row + " (" + page + ")" }
    }

    struct Report: CustomStringConvertible {
        var searches: [Ask: [Found]]
        var pages: [String: String]
        var status: Int32
        var output: String
        func found(_ ask: Ask) -> [Found]? { searches[ask] }
        func page(_ row: String) -> String? { pages[row] }
        var description: String { "(the child exited \(status)):\n\(output)" }
    }

    struct Failure: Error, CustomStringConvertible { var description: String }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    static var thirdParty: URL {
        ProcessInfo.processInfo.environment["ALLINONEIME_THIRDPARTY"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("ThirdParty")
    }

    /// The child run with `asks`, what it printed read back.
    static func run(_ asks: [Ask]) throws -> Report {
        let executable = try compiled.get()
        let fm = FileManager.default
        // The child's home: never the user's config.
        let home = fm.temporaryDirectory.appendingPathComponent("settings075-home-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let result = try command(executable, asks.map(\.argument), environment: ["CFFIXED_USER_HOME": home.path, "HOME": home.path],
                                 timeout: 60)
        var searches: [Ask: [Found]] = [:], pages: [String: String] = [:]
        for line in result.output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if fields.first == "FOUND", fields.count == 5, let variant = Variant(rawValue: fields[1]) {
                searches[Ask(variant, fields[2], fields[3])] = fields[4].split(separator: ",").compactMap { pair in
                    let parts = pair.split(separator: ":").map(String.init)
                    return parts.count == 2 ? Found(parts[0], parts[1]) : nil
                }
            } else if fields.first == "PAGE", fields.count == 3 {
                pages[fields[1]] = fields[2]
            }
        }
        if result.status != 0 { throw Failure(description: "the child failed (\(result.status)):\n\(result.output)") }
        return Report(searches: searches, pages: pages, status: result.status, output: result.output)
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("settings075-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        // main.swift as written up to its dispatch, then the harness.
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.upperBound]) + Settings075Harness.swift).write(to: mainFile, atomically: true, encoding: .utf8)
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
        let executable = scratch.appendingPathComponent("settings075")
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
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("settings075-\(UUID().uuidString).log")
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

/// What follows main.swift's `let arguments = …` in the child: each argument a variant of the config, an interface
/// language and a query (tab-separated); each searched as the sidebar searches (a `FOUND` line: the rows found, each
/// with its page), or a row's page told (a `PAGE` line; "none": no such row).
private enum Settings075Harness {
    static let swift = #"""

// MARK: - Settings075MacTests' child (in place of main.swift's dispatch)

MainActor.assumeIsolated {
    // Never the user's config: the test's home.
    let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
    guard !home.isEmpty, Config.defaultURL.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
        print("FAIL the config file isn't in the test's home: \(Config.defaultURL.path)")
        exit(3)
    }
    for argument in arguments {
        let parts = argument.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else {
            print("FAIL usage: VARIANT<tab>INTERFACE<tab>QUERY, not \(argument)")
            exit(2)
        }
        let (variant, interface, query) = (parts[0], parts[1], parts[2])
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        switch variant {
        case "plain": break
        case "jargon": config.jargonFile = "~/team-jargon.txt"
        case "selectionOff": config.useSelection = false
        default:
            print("FAIL no variant \(variant)")
            exit(2)
        }
        config.uiLanguage = interface
        UIText.choice = interface
        if query.hasPrefix("page:") {
            let row = String(query.dropFirst("page:".count))
            print("PAGE\t\(row)\t\(SettingsSpot(rawValue: row)?.page.rawValue ?? "none")")
            continue
        }
        // A row's own title, as the interface says it; else what is typed.
        let typed: String
        if query.hasPrefix("title:") {
            guard let spot = SettingsSpot(rawValue: String(query.dropFirst("title:".count))) else {
                print("FAIL no row \(query)")
                exit(2)
            }
            typed = spot.title
        } else {
            typed = query
        }
        // As the sidebar searches (SettingsWindow: what is typed in its search field, with the window's config).
        let found = SettingsSpot.search(typed, trigger: config.commandTrigger, config: config)
        print("FOUND\t\(variant)\t\(interface)\t\(query)\t\(found.map { $0.rawValue + ":" + $0.page.rawValue }.joined(separator: ","))")
    }
    fflush(stdout)
}
exit(0)
"""#
}
